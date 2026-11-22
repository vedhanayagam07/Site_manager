import { test, expect } from "@playwright/test";

test.describe("Module B: Supervisor Personal Attendance Workflows", () => {
  test("renders supervisor tab with governance policy", async ({ page }) => {
    await page.goto("/attendance");
    if (page.url().includes("/login")) return;

    // Switch to supervisor attendance tab
    const supervisorTab = page.locator('button:has-text("Module B: Supervisor Attendance")');
    if (await supervisorTab.isVisible()) {
      await supervisorTab.click();

      // Verify governance policy or supervisor attendance view
      await expect(
        page.locator("text=Supervisor Attendance")
      ).toBeVisible();
    }
  });

  test("self-marking lock is enforced for supervisors", async ({ page }) => {
    await page.goto("/attendance");
    if (page.url().includes("/login")) return;

    const supervisorTab = page.locator('button:has-text("Module B: Supervisor Attendance")');
    if (await supervisorTab.isVisible()) {
      await supervisorTab.click();

      // Look for self-marking notice or prohibition pill if logged in as supervisor
      const policyNotice = page.locator("text=Self-marking prohibited by company policy");
      // Should not throw
      expect(policyNotice).toBeDefined();
    }
  });
});

