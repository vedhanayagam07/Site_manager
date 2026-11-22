import { createClient } from "@/lib/supabase/client";
import { logActivity } from "@/lib/data/activity-logs";
import type {
  CreateProgressUpdateInput,
  ProgressFilterOptions,
  SiteProgressPhotoRecord,
  SiteProgressUpdateRecord,
  UserProfile,
} from "@/types/database";

export const SITE_PROGRESS_BUCKET = "site-progress-photos";

export interface ProgressQueryResult {
  tableReady: boolean;
  records: SiteProgressUpdateRecord[];
  error?: string | null;
}

export interface PreparedUploadPhoto {
  file: Blob | File;
  name: string;
  sizeBytes: number;
  caption?: string;
  previewUrl: string;
}

/**
 * Helper to test whether an error indicates missing tables or missing storage bucket.
 */
function isSchemaNotReadyError(error: unknown): boolean {
  if (!error) return false;
  const msg = (typeof error === "object" && error !== null && "message" in error)
    ? String((error as { message: unknown }).message).toLowerCase()
    : "";
  const code = (typeof error === "object" && error !== null && "code" in error)
    ? String((error as { code?: string }).code)
    : "";

  return (
    code === "42P01" ||
    code === "PGRST205" ||
    code === "42501" ||
    msg.includes("does not exist") ||
    msg.includes("schema cache") ||
    msg.includes("bucket not found") ||
    msg.includes("not found")
  );
}

/**
 * Fetch site progress updates with attached photos and user profile details.
 * Automatically generates secure short-lived signed URLs for all attached photos.
 */
export async function fetchSiteProgressUpdates(
  options?: ProgressFilterOptions
): Promise<ProgressQueryResult> {
  const supabase = createClient();

  try {
    let query = supabase
      .from("site_progress_updates")
      .select(`
        id,
        site_id,
        work_date,
        category,
        description,
        remarks,
        feedback,
        feedback_by,
        feedback_at,
        created_by,
        created_at,
        updated_at,
        sites (id, name, location),
        photos:site_progress_photos (*)
      `)
      .order("work_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (options?.siteId) {
      query = query.eq("site_id", options.siteId);
    }
    if (options?.category) {
      query = query.eq("category", options.category);
    }
    if (options?.startDate) {
      query = query.gte("work_date", options.startDate);
    }
    if (options?.endDate) {
      query = query.lte("work_date", options.endDate);
    }

    const { data, error } = await query;

    if (error) {
      if (isSchemaNotReadyError(error)) {
        return { tableReady: false, records: [] };
      }
      throw error;
    }

    const updates = (data ?? []) as unknown as SiteProgressUpdateRecord[];

    // Collect all storage paths to create batch signed URLs (3600 seconds = 1 hour validity)
    const allPaths: string[] = [];
    for (const update of updates) {
      if (Array.isArray(update.photos)) {
        for (const photo of update.photos) {
          if (photo.storage_path) {
            allPaths.push(photo.storage_path);
          }
        }
      }
    }

    // Map of storage_path -> signed_url
    const signedUrlMap = new Map<string, string>();
    if (allPaths.length > 0) {
      try {
        const { data: signedData, error: signError } = await supabase.storage
          .from(SITE_PROGRESS_BUCKET)
          .createSignedUrls(allPaths, 3600);

        if (!signError && Array.isArray(signedData)) {
          for (const item of signedData) {
            if (item.path && item.signedUrl) {
              signedUrlMap.set(item.path, item.signedUrl);
            }
          }
        }
      } catch (signErr) {
        console.warn("[SiteProgress] Could not generate batch signed URLs:", signErr);
      }
    }

    // Also fetch creator and reviewer profile names in a single batch
    const userIds = new Set<string>();
    for (const update of updates) {
      if (update.created_by) userIds.add(update.created_by);
      if (update.feedback_by) userIds.add(update.feedback_by);
    }

    const userProfileMap = new Map<string, UserProfile>();
    if (userIds.size > 0) {
      try {
        const { data: profiles } = await supabase
          .from("user_profiles")
          .select("id, name, email, role, status")
          .in("id", Array.from(userIds));

        if (profiles) {
          for (const p of profiles as UserProfile[]) {
            userProfileMap.set(p.id, p);
          }
        }
      } catch {
        // Safe to ignore if user_profiles query fails
      }
    }

    // Enrich updates with signed URLs and profile info
    const enrichedUpdates = updates.map((update) => {
      const photos = (update.photos || []).map((photo) => ({
        ...photo,
        signed_url: signedUrlMap.get(photo.storage_path) || undefined,
      }));

      return {
        ...update,
        photos,
        creator_profile: update.created_by
          ? userProfileMap.get(update.created_by) || null
          : null,
        reviewer_profile: update.feedback_by
          ? userProfileMap.get(update.feedback_by) || null
          : null,
      };
    });

    return {
      tableReady: true,
      records: enrichedUpdates,
    };
  } catch (err: unknown) {
    if (isSchemaNotReadyError(err)) {
      return { tableReady: false, records: [] };
    }
    return {
      tableReady: false,
      records: [],
      error: err instanceof Error ? err.message : "Failed to load progress records",
    };
  }
}

/**
 * Creates a new daily site progress record and uploads multiple compressed photos
 * into the private Supabase Storage bucket following path convention:
 * sites/{site_id}/{progress_id}/{photo_id}.jpg
 */
export async function createSiteProgressUpdate(
  input: CreateProgressUpdateInput,
  photos: PreparedUploadPhoto[],
  siteName: string,
  onProgress?: (percent: number, statusText: string) => void
): Promise<{ success: boolean; progressId?: string; error?: string }> {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { success: false, error: "User is not authenticated." };
  }

  onProgress?.(5, "Initializing progress record...");

  const progressId = crypto.randomUUID();
  const now = new Date().toISOString();

  // 1. Insert header record in site_progress_updates
  const { error: insertError } = await supabase
    .from("site_progress_updates")
    .insert({
      id: progressId,
      site_id: input.site_id,
      work_date: input.work_date,
      category: input.category,
      description: input.description.trim(),
      remarks: input.remarks?.trim() || null,
      created_by: user.id,
      created_at: now,
      updated_at: now,
    });

  if (insertError) {
    if (isSchemaNotReadyError(insertError)) {
      return {
        success: false,
        error:
          "The 'site_progress_updates' table has not been created yet in Supabase. Please apply the migration proposal in supabase/migrations/20261120_site_progress_photos_PROPOSAL.sql.",
      };
    }
    return { success: false, error: insertError.message };
  }

  onProgress?.(25, "Uploading photos to secure storage...");

  // 2. Upload photos to private Supabase Storage bucket
  const photoRecords: Array<{
    id: string;
    progress_id: string;
    site_id: string;
    storage_path: string;
    caption: string | null;
    file_size: number;
    mime_type: string;
    uploaded_by: string;
    created_at: string;
  }> = [];

  const totalPhotos = photos.length;
  for (let i = 0; i < totalPhotos; i++) {
    const p = photos[i];
    const photoId = crypto.randomUUID();
    const storagePath = `sites/${input.site_id}/${progressId}/${photoId}.jpg`;

    const progressStep = 25 + Math.round(((i + 1) / totalPhotos) * 55);
    onProgress?.(
      progressStep,
      `Uploading photo ${i + 1} of ${totalPhotos}...`
    );

    const { error: uploadError } = await supabase.storage
      .from(SITE_PROGRESS_BUCKET)
      .upload(storagePath, p.file, {
        contentType: "image/jpeg",
        upsert: false,
      });

    if (uploadError) {
      console.error("[SiteProgress] Storage upload failed:", uploadError);
      // Clean up newly created header record if photo upload fails midway
      try {
        await supabase.from("site_progress_updates").delete().eq("id", progressId);
      } catch (cleanupErr) {
        console.warn("[SiteProgress] Header rollback warning:", cleanupErr);
      }
      if (isSchemaNotReadyError(uploadError)) {
        return {
          success: false,
          error: `Storage upload failed: The private bucket '${SITE_PROGRESS_BUCKET}' does not exist or access was denied. Please apply the migration proposal.`,
        };
      }
      return {
        success: false,
        error: `Photo upload failed (${i + 1}/${totalPhotos}): ${uploadError.message}`,
      };
    }

    photoRecords.push({
      id: photoId,
      progress_id: progressId,
      site_id: input.site_id,
      storage_path: storagePath,
      caption: p.caption?.trim() || null,
      file_size: p.sizeBytes,
      mime_type: "image/jpeg",
      uploaded_by: user.id,
      created_at: now,
    });
  }

  // 3. Insert photo metadata records if any photos were attached
  if (photoRecords.length > 0) {
    onProgress?.(85, "Saving photo references...");
    const { error: photoInsertError } = await supabase
      .from("site_progress_photos")
      .insert(photoRecords);

    if (photoInsertError) {
      console.error("[SiteProgress] Photo metadata insert error:", photoInsertError);
      try {
        await supabase.from("site_progress_updates").delete().eq("id", progressId);
      } catch (cleanupErr) {
        console.warn("[SiteProgress] Header rollback warning:", cleanupErr);
      }
      return {
        success: false,
        error: `Failed to link photo metadata: ${photoInsertError.message}`,
      };
    }
  }

  onProgress?.(95, "Logging activity...");

  // 4. Log activity
  await logActivity({
    action: "Site Progress Uploaded",
    module: "Site Progress",
    description: `Added progress update for ${input.category} on ${siteName} (${input.work_date}) with ${totalPhotos} photo(s)`,
    newValue: `${totalPhotos} photo(s) - ${input.category}`,
  });

  onProgress?.(100, "Done!");
  return { success: true, progressId };
}

/**
 * Add or update Project Manager / Admin feedback comments on a site progress update.
 */
export async function addProgressFeedback(
  progressId: string,
  feedbackText: string,
  siteName?: string
): Promise<{ success: boolean; error: string | null }> {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { success: false, error: "Authentication required." };
  }

  const now = new Date().toISOString();
  const { error } = await supabase
    .from("site_progress_updates")
    .update({
      feedback: feedbackText.trim(),
      feedback_by: user.id,
      feedback_at: now,
      updated_at: now,
    })
    .eq("id", progressId);

  if (error) {
    return { success: false, error: error.message };
  }

  await logActivity({
    action: "Progress Feedback Added",
    module: "Site Progress",
    description: `Added feedback comment on site progress (${siteName || "Site"})`,
    newValue: feedbackText.trim().slice(0, 100),
  });

  return { success: true, error: null };
}

/**
 * Delete a site progress update and its associated storage photos.
 * Restricted to Project Managers and Administrators.
 */
export async function deleteSiteProgressUpdate(
  progressId: string,
  photos: SiteProgressPhotoRecord[],
  siteName?: string
): Promise<{ success: boolean; error: string | null }> {
  const supabase = createClient();

  // 1. Delete photos from storage bucket
  const paths = photos.map((p) => p.storage_path).filter(Boolean);
  if (paths.length > 0) {
    try {
      await supabase.storage.from(SITE_PROGRESS_BUCKET).remove(paths);
    } catch (storageErr) {
      console.warn("[SiteProgress] Could not remove storage files:", storageErr);
    }
  }

  // 2. Delete update row (DB foreign key cascades to site_progress_photos)
  const { error } = await supabase
    .from("site_progress_updates")
    .delete()
    .eq("id", progressId);

  if (error) {
    return { success: false, error: error.message };
  }

  await logActivity({
    action: "Site Progress Deleted",
    module: "Site Progress",
    description: `Deleted site progress update (${progressId}) for ${siteName || "Site"}`,
  });

  return { success: true, error: null };
}

/**
 * Generate a fresh 1-hour signed URL for a single photo storage path.
 */
export async function getSignedPhotoUrl(
  storagePath: string
): Promise<string | null> {
  const supabase = createClient();
  try {
    const { data, error } = await supabase.storage
      .from(SITE_PROGRESS_BUCKET)
      .createSignedUrl(storagePath, 3600);

    if (error || !data) return null;
    return data.signedUrl;
  } catch {
    return null;
  }
}

