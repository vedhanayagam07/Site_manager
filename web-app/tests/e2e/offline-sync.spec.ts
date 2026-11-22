import { test, expect } from "@playwright/test";

test.describe("Offline Readiness & Outbox Engine", () => {
  test("offline banner triggers when connection is severed", async ({ page, context }) => {
    await page.goto("/attendance");
    if (page.url().includes("/login")) return;

    // Simulate going offline
    await context.setOffline(true);

    // Verify offline banner appears
    const offlinePill = page.locator("text=Offline");
    await expect(offlinePill).toBeVisible({ timeout: 5000 });

    // Restore online
    await context.setOffline(false);
  });

  test("settings diagnostics displays outbox manager and PWA status", async ({ page }) => {
    await page.goto("/settings");
    if (page.url().includes("/login")) return;

    await expect(page.locator("text=Offline Outbox & Sync Engine")).toBeVisible();
    await expect(page.locator("text=Progressive Web App (PWA)")).toBeVisible();
  });
});

