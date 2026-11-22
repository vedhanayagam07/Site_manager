"use client";

import React, { useRef, useState } from "react";
import { Camera, ImagePlus, X, Trash2, CheckCircle2, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { PreparedUploadPhoto } from "@/lib/data/site-progress";

interface MultiPhotoCaptureProps {
  photos: PreparedUploadPhoto[];
  onChange: (photos: PreparedUploadPhoto[]) => void;
  maxPhotos?: number;
  disabled?: boolean;
}

/**
 * Mobile-first Multi-Photo Capture & Client-Side Compression Component.
 * - Supports instant camera capture (HTML5 capture="environment" for rear camera)
 * - Supports selecting multiple images simultaneously from device gallery
 * - Resizes large photos client-side to max 1280px (under 250KB JPEG)
 * - Provides thumbnail previews, individual photo removal, and captioning
 */
export function MultiPhotoCapture({
  photos,
  onChange,
  maxPhotos = 12,
  disabled = false,
}: MultiPhotoCaptureProps) {
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const galleryInputRef = useRef<HTMLInputElement>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [processingStatus, setProcessingStatus] = useState<string>("");

  /**
   * Resizes an image file to max 1280px and compresses to JPEG ~0.75 quality.
   */
  async function compressImageFile(file: File): Promise<PreparedUploadPhoto> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error(`Failed to read file: ${file.name}`));
      reader.onload = (e) => {
        const img = new Image();
        img.onerror = () => reject(new Error(`Failed to load image: ${file.name}`));
        img.onload = () => {
          const maxDim = 1280;
          let width = img.width;
          let height = img.height;

          if (width > height && width > maxDim) {
            height = Math.round((height * maxDim) / width);
            width = maxDim;
          } else if (height > maxDim) {
            width = Math.round((width * maxDim) / height);
            height = maxDim;
          }

          const canvas = document.createElement("canvas");
          canvas.width = width;
          canvas.height = height;
          const ctx = canvas.getContext("2d");
          if (!ctx) {
            reject(new Error("Canvas context unavailable"));
            return;
          }

          ctx.drawImage(img, 0, 0, width, height);
          canvas.toBlob(
            (blob) => {
              if (!blob) {
                reject(new Error("Canvas toBlob failed"));
                return;
              }
              const previewUrl = URL.createObjectURL(blob);
              resolve({
                file: blob,
                name: file.name || `photo-${Date.now()}.jpg`,
                sizeBytes: blob.size,
                previewUrl,
              });
            },
            "image/jpeg",
            0.78
          );
        };
        img.src = e.target?.result as string;
      };
      reader.readAsDataURL(file);
    });
  }

  async function handleFilesSelected(fileList: FileList | null) {
    if (!fileList || fileList.length === 0) return;

    const remainingSlots = maxPhotos - photos.length;
    if (remainingSlots <= 0) return;

    const filesToProcess = Array.from(fileList).slice(0, remainingSlots);
    setIsProcessing(true);
    setProcessingStatus(`Optimizing ${filesToProcess.length} photo(s)...`);

    try {
      const newPhotos: PreparedUploadPhoto[] = [];
      for (let i = 0; i < filesToProcess.length; i++) {
        setProcessingStatus(
          `Optimizing photo ${i + 1} of ${filesToProcess.length}...`
        );
        const compressed = await compressImageFile(filesToProcess[i]);
        newPhotos.push(compressed);
      }
      onChange([...photos, ...newPhotos]);
    } catch (err) {
      console.error("[MultiPhotoCapture] Error compressing photos:", err);
    } finally {
      setIsProcessing(false);
      setProcessingStatus("");
      if (cameraInputRef.current) cameraInputRef.current.value = "";
      if (galleryInputRef.current) galleryInputRef.current.value = "";
    }
  }

  function handleRemovePhoto(index: number) {
    const photoToRemove = photos[index];
    if (photoToRemove?.previewUrl) {
      URL.revokeObjectURL(photoToRemove.previewUrl);
    }
    const next = photos.filter((_, i) => i !== index);
    onChange(next);
  }

  function handleCaptionChange(index: number, caption: string) {
    const next = photos.map((p, i) => (i === index ? { ...p, caption } : p));
    onChange(next);
  }

  function handleClearAll() {
    photos.forEach((p) => {
      if (p.previewUrl) URL.revokeObjectURL(p.previewUrl);
    });
    onChange([]);
  }

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const isAtCapacity = photos.length >= maxPhotos;

  return (
    <div className="space-y-3">
      {/* Hidden file inputs */}
      <input
        ref={cameraInputRef}
        type="file"
        accept="image/*"
        capture="environment"
        className="hidden"
        disabled={disabled || isAtCapacity || isProcessing}
        onChange={(e) => handleFilesSelected(e.target.files)}
      />
      <input
        ref={galleryInputRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        disabled={disabled || isAtCapacity || isProcessing}
        onChange={(e) => handleFilesSelected(e.target.files)}
      />

      {/* Action buttons */}
      <div className="flex flex-wrap items-center gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled || isAtCapacity || isProcessing}
          onClick={() => cameraInputRef.current?.click()}
          className="flex items-center gap-1.5 touch-manipulation cursor-pointer"
        >
          <Camera className="h-4 w-4 text-[#2563EB]" />
          <span>Take Photo</span>
        </Button>

        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled || isAtCapacity || isProcessing}
          onClick={() => galleryInputRef.current?.click()}
          className="flex items-center gap-1.5 touch-manipulation cursor-pointer"
        >
          <ImagePlus className="h-4 w-4 text-emerald-600" />
          <span>Add from Gallery</span>
        </Button>

        {photos.length > 0 && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            disabled={disabled || isProcessing}
            onClick={handleClearAll}
            className="text-xs text-rose-600 hover:bg-rose-50 hover:text-rose-700 ml-auto cursor-pointer"
          >
            <Trash2 className="h-3.5 w-3.5 mr-1" />
            Clear All ({photos.length})
          </Button>
        )}
      </div>

      {/* Processing indicator */}
      {isProcessing && (
        <div className="flex items-center gap-2 rounded-lg bg-blue-50 px-3 py-2 text-xs font-medium text-blue-700">
          <Loader2 className="h-4 w-4 animate-spin shrink-0 text-[#2563EB]" />
          <span>{processingStatus || "Compressing image..."}</span>
        </div>
      )}

      {/* Photos Thumbnail Grid */}
      {photos.length > 0 ? (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 pt-1">
          {photos.map((photo, idx) => (
            <div
              key={idx}
              className="group relative rounded-xl border border-slate-200 bg-white p-2 shadow-2xs hover:border-slate-300 transition-all flex flex-col justify-between"
            >
              <div className="relative aspect-4/3 w-full overflow-hidden rounded-lg bg-slate-100">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={photo.previewUrl}
                  alt={photo.name}
                  className="h-full w-full object-cover"
                />
                <button
                  type="button"
                  onClick={() => handleRemovePhoto(idx)}
                  disabled={disabled}
                  aria-label="Remove photo"
                  className="absolute top-1.5 right-1.5 rounded-full bg-slate-900/80 p-1 text-white shadow-sm hover:bg-rose-600 transition-colors cursor-pointer"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
                <div className="absolute bottom-1 left-1.5 rounded bg-black/60 px-1.5 py-0.5 text-[10px] font-semibold text-white">
                  #{idx + 1} • {formatSize(photo.sizeBytes)}
                </div>
              </div>

              {/* Caption input */}
              <div className="mt-2">
                <input
                  type="text"
                  placeholder="Optional caption..."
                  value={photo.caption || ""}
                  disabled={disabled}
                  onChange={(e) => handleCaptionChange(idx, e.target.value)}
                  className="w-full rounded border border-slate-200 px-2 py-1 text-xs text-slate-800 placeholder-slate-400 focus:border-[#2563EB] focus:outline-hidden"
                />
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div
          onClick={() => {
            if (!disabled && !isProcessing) {
              cameraInputRef.current?.click();
            }
          }}
          className="flex flex-col items-center justify-center rounded-xl border-2 border-dashed border-slate-200 p-6 text-center hover:border-slate-300 transition-colors cursor-pointer bg-slate-50/50"
        >
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-blue-50 text-[#2563EB] mb-2">
            <Camera className="h-5 w-5" />
          </div>
          <p className="text-xs font-semibold text-slate-700">
            No photos attached yet
          </p>
          <p className="text-[11px] text-slate-500 mt-0.5">
            Tap to open camera or use buttons above to select from gallery (up to {maxPhotos} photos)
          </p>
        </div>
      )}

      {/* Capacity tracker */}
      <div className="flex items-center justify-between text-[11px] text-slate-500 px-0.5">
        <span>
          {photos.length} of {maxPhotos} photos attached
        </span>
        <span className="text-emerald-600 font-medium flex items-center gap-1">
          <CheckCircle2 className="h-3 w-3" /> Auto-compressed for fast 4G upload
        </span>
      </div>
    </div>
  );
}

