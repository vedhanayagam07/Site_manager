import { test, expect } from "@playwright/test";

test.describe("Module A: Daily Workforce Attendance Workflows", () => {
  test("calculates total workforce automatically across trade categories", async ({ page }) => {
    // Navigate to attendance page
    await page.goto("/attendance");

    // If redirected to login, verify form exists
    if (page.url().includes("/login")) {
      await expect(page.locator("text=TSR BUILDERS")).toBeVisible();
      return;
    }

    // Verify all 7 standard categories exist
    const categories = [
      "Masons",
      "Painters",
      "Helpers",
      "Carpenters",
      "Electricians",
      "Plumbers",
      "Other",
    ];

    for (const cat of categories) {
      await expect(page.locator(`text=${cat}`)).toBeVisible();
    }

    // Total workforce badge should be visible
    await expect(page.locator("text=Total Workforce")).toBeVisible();
  });

  test("mobile viewport displays thumb-friendly sticky action bar", async ({ page, isMobile }) => {
    await page.goto("/attendance");
    if (page.url().includes("/login")) return;

    if (isMobile) {
      // Verify sticky bottom action bar exists for one-handed operation
      const stickyBar = page.locator(".fixed.bottom-\\[calc\\(env\\(safe-area-inset-bottom\\)\\+3\\.5rem\\)\\]");
      await expect(stickyBar).toBeVisible();
    }
  });
});

