import { z } from "zod";

export const siteFormSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "Site name must be at least 2 characters.")
    .max(120, "Site name must be under 120 characters."),
  location: z.string().trim().max(200, "Location is too long."),
  project_manager: z.string().trim().max(100, "Manager name is too long."),
  status: z.enum(["Active", "On Hold", "Completed"]),
  progress: z.coerce
    .number()
    .int("Progress must be a whole number.")
    .min(0, "Progress cannot be less than 0%.")
    .max(100, "Progress cannot exceed 100%."),
});

export const workerFormSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "Worker name must be at least 2 characters.")
    .max(100, "Worker name is too long."),
  phone: z
    .string()
    .trim()
    .regex(/^\d{10}$/, "Phone number must be exactly 10 digits."),
  role: z.string().trim().min(1, "Please select a role."),
  skill: z.string().trim().min(1, "Please select a skill set."),
  status: z.enum(["Active", "Inactive"]),
  site_id: z.string().nullable(),
});

export const materialFormSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "Material name must be at least 2 characters.")
    .max(120, "Material name is too long."),
  unit: z.string().trim().min(1, "Please select a unit."),
  supplier: z.string().trim().max(120, "Supplier name is too long."),
  site_id: z.string().min(1, "Please assign the material to a site."),
});

export const stockMovementSchema = z
  .object({
    materialId: z.string().min(1, "Select a material."),
    transactionType: z.enum(["RECEIVED", "USED"]),
    quantity: z.coerce
      .number()
      .positive("Quantity must be greater than 0."),
    siteName: z.string().trim(),
    remarks: z.string().trim().max(300, "Remarks must be under 300 characters."),
  })
  .refine(
    (data) => data.transactionType !== "USED" || data.siteName.length > 0,
    {
      path: ["siteName"],
      message: "Selecting an active site is required when logging stock usage.",
    }
  );

export const loadingMemoSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Select a valid dispatch date."),
  vehicle_number: z
    .string()
    .trim()
    .min(4, "Enter a valid vehicle registration number.")
    .max(30, "Vehicle number is too long."),
  material_name: z
    .string()
    .trim()
    .min(2, "Select or enter a material name."),
  quantity: z.coerce.number().positive("Quantity must be greater than 0."),
  unit: z.string().trim().min(1, "Select a unit."),
  remarks: z.string().trim().max(300, "Remarks are too long."),
});

export const adminCreateUserSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "Full name must be between 2 and 100 characters.")
    .max(100, "Full name must be between 2 and 100 characters."),
  email: z
    .string()
    .trim()
    .email("Enter a valid email address.")
    .max(255, "Email is too long."),
  password: z
    .string()
    .min(8, "Password must be at least 8 characters.")
    .max(72, "Password must be 72 characters or fewer."),
  role: z.enum(["admin", "projectManager", "supervisor"]),
  status: z.enum(["active", "disabled"]),
});

export const adminUpdateUserSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "Full name must be between 2 and 100 characters.")
    .max(100, "Full name must be between 2 and 100 characters."),
  role: z.enum(["admin", "projectManager", "supervisor"]),
  status: z.enum(["active", "disabled"]),
});

export function extractFieldErrors(
  zodError: z.ZodError
): Record<string, string> {
  const map: Record<string, string> = {};
  for (const issue of zodError.issues) {
    const key = String(issue.path[0] ?? "_form");
    if (!map[key]) {
      map[key] = issue.message;
    }
  }
  return map;
}

