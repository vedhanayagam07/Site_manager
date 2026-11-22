// Strict TypeScript definitions matching the verified TSR Builders Supabase schema.
// All table and column names are verified against the existing Flutter app and SQL migrations.

export type AppRole = "admin" | "projectManager" | "supervisor";
export type AccountStatus = "active" | "disabled";

export interface UserProfile {
  id: string;
  email: string;
  name: string;
  role: AppRole;
  status: AccountStatus;
  created_at?: string | null;
}

export interface SiteRecord {
  id: string;
  name: string;
  location: string | null;
  project_manager: string | null;
  status: string; // 'Active' | 'On Hold' | 'Completed'
  progress?: number | null;
  created_at?: string | null;
}

export interface WorkerRecord {
  id: string;
  name: string;
  phone: string | null;
  role: string | null; // 'Mason' | 'Carpenter' | 'Electrician' | 'Plumber' | 'Painter' | 'Supervisor' | 'Site Engineer' | 'Contractor'
  skill: string | null;
  status: string; // 'Active' | 'Inactive'
  site_id: string | null;
  assigned_site: string | null;
  created_at?: string | null;
}

export type AttendanceStatus = "Present" | "Absent" | "Half Day";

export interface SiteAttendanceRecord {
  id: string;
  worker_id: string;
  site_id: string;
  attendance_date: string; // YYYY-MM-DD
  status: AttendanceStatus;
  created_at?: string | null;
  workers?: { name: string | null; role: string | null } | null;
  sites?: { name: string | null } | null;
}

export interface DailyWorkforceCountRecord {
  id: string;
  site_id: string;
  attendance_date: string; // YYYY-MM-DD
  category: string; // e.g., 'Mason', 'Helper', 'Carpenter', 'Electrician', 'Plumber', 'Painter', 'Bar Bender'
  count: number;
  notes?: string | null;
  recorded_by?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  sites?: { name: string | null } | null;
}

// Module A: Daily Workforce Attendance (Parent Header & Category Counts)
export interface DailyWorkforceCategoryCount {
  id: string;
  attendance_id: string;
  site_id: string;
  category: string;
  count: number;
  full_day_count?: number;
  half_day_count?: number;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface DailyWorkforceAttendanceRecord {
  id: string;
  site_id: string;
  attendance_date: string; // YYYY-MM-DD
  remarks: string | null;
  total_workforce: number;
  total_man_days?: number | null;
  created_by: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  sites?: { name: string | null } | null;
  category_counts?: DailyWorkforceCategoryCount[];
}

// Module B: Supervisor Personal Attendance
export type SupervisorAttendanceStatus = "Present" | "Absent" | "Half Day" | "Leave";

export interface SupervisorAttendanceRecord {
  id: string;
  supervisor_id: string;
  site_id: string;
  attendance_date: string; // YYYY-MM-DD
  status: SupervisorAttendanceStatus;
  remarks: string | null;
  recorded_by: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  supervisor?: UserProfile | null;
  sites?: { name: string | null } | null;
}

// Site Membership / Assignment Junction (reusing live site_memberships)
export interface SiteMembershipRecord {
  id?: string;
  site_id: string;
  user_id: string;
  role?: string | null;
  created_at?: string | null;
  user_profile?: UserProfile | null;
  sites?: SiteRecord | null;
}

// Backward-compatible alias
export type SiteSupervisorRecord = SiteMembershipRecord;

export interface MaterialRecord {
  id: string;
  name: string;
  unit: string; // 'Bags' | 'Kg' | 'Loads' | 'Nos'
  supplier: string | null;
  site_id: string | null;
  received_qty: number | null;
  used_qty: number | null;
  balance_qty: number | null;
  minimum_stock?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export type MaterialTransactionType = "RECEIVED" | "USED";

export interface MaterialTransactionRecord {
  id: string;
  material_id: string;
  transaction_type: MaterialTransactionType;
  quantity: number;
  site_name: string | null;
  remarks: string | null;
  created_at: string;
  materials?: { name: string | null; unit?: string | null } | null;
}

export interface LoadingMemoRecord {
  id: string;
  date: string; // YYYY-MM-DD
  vehicle_number: string;
  material_id: string | null;
  material_name: string;
  quantity: number;
  unit: string;
  remarks: string | null;
  generated_by: string;
  created_at: string;
}

export interface ActivityLogRecord {
  id: string;
  user_id: string | null;
  user_name: string | null;
  role: string | null;
  action: string;
  module: string;
  old_value: string | null;
  new_value: string | null;
  description: string | null;
  created_at: string;
}

export const WORKER_ROLES = [
  "Mason",
  "Helper",
  "Carpenter",
  "Electrician",
  "Plumber",
  "Painter",
  "Bar Bender",
  "Supervisor",
  "Site Engineer",
  "Contractor",
] as const;

export const DAILY_WORKFORCE_CATEGORIES = [
  "Mason",
  "Helper",
  "Carpenter",
  "Electrician",
  "Plumber",
  "Painter",
  "Bar Bender",
  "Welder",
] as const;

// Module A: Standard Workforce Categories per TSR Specifications
export const STANDARD_WORKFORCE_CATEGORIES = [
  "Masons",
  "Painters",
  "Helpers",
  "Carpenters",
  "Electricians",
  "Plumbers",
  "Other",
] as const;

export type StandardWorkforceCategory = (typeof STANDARD_WORKFORCE_CATEGORIES)[number];

// Module B: Supervisor Attendance Statuses
export const SUPERVISOR_ATTENDANCE_STATUSES = [
  "Present",
  "Absent",
  "Half Day",
  "Leave",
] as const;

export const WORKER_SKILLS = [
  "Civil Work",
  "Electrical",
  "Plumbing",
  "Steel Fixing",
  "Concrete Work",
  "Finishing",
] as const;

export const MATERIAL_UNITS = ["Bags", "Kg", "Loads", "Nos", "Tons", "Cft"] as const;

export const SITE_STATUSES = ["Active", "On Hold", "Completed"] as const;

// Daily Site Progress & Photo Gallery Module
export const PROGRESS_WORK_CATEGORIES = [
  "Excavation",
  "Foundation",
  "Reinforcement",
  "Concrete",
  "Masonry",
  "Plastering",
  "Electrical",
  "Plumbing",
  "Painting",
  "Flooring",
  "Roofing",
  "Finishing",
  "Other",
] as const;

export type ProgressWorkCategory = (typeof PROGRESS_WORK_CATEGORIES)[number];

export interface SiteProgressPhotoRecord {
  id: string;
  progress_id: string;
  site_id: string;
  storage_path: string;
  caption: string | null;
  file_size: number | null;
  mime_type: string | null;
  uploaded_by: string | null;
  created_at: string;
  signed_url?: string;
}

export interface SiteProgressUpdateRecord {
  id: string;
  site_id: string;
  work_date: string; // YYYY-MM-DD
  category: ProgressWorkCategory | string;
  description: string;
  remarks: string | null;
  feedback: string | null;
  feedback_by: string | null;
  feedback_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  sites?: { name: string | null; location?: string | null } | null;
  creator_profile?: UserProfile | null;
  reviewer_profile?: UserProfile | null;
  photos?: SiteProgressPhotoRecord[];
}

export interface CreateProgressUpdateInput {
  site_id: string;
  work_date: string;
  category: ProgressWorkCategory | string;
  description: string;
  remarks?: string | null;
}

export interface ProgressFilterOptions {
  siteId?: string;
  startDate?: string;
  endDate?: string;
  category?: string;
}


