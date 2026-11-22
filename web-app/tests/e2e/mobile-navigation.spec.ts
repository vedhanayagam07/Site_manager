import { test, expect } from "@playwright/test";

test.describe("Mobile-First Navigation & Responsive Layouts", () => {
  test("mobile view shows bottom tab bar and hides desktop sidebar", async ({ page, isMobile }) => {
    await page.goto("/dashboard");
    if (page.url().includes("/login")) return;

    if (isMobile) {
      // Mobile bottom nav must be visible
      const bottomNav = page.locator('nav[aria-label="Mobile quick navigation"]');
      await expect(bottomNav).toBeVisible();

      // Desktop sidebar should be hidden
      const desktopSidebar = page.locator("aside");
      await expect(desktopSidebar).not.toBeVisible();
    } else {
      // Desktop sidebar should be visible
      const desktopSidebar = page.locator("aside");
      await expect(desktopSidebar).toBeVisible();

      // Mobile bottom nav should be hidden
      const bottomNav = page.locator('nav[aria-label="Mobile quick navigation"]');
      await expect(bottomNav).not.toBeVisible();
    }
  });

  test("tables avoid horizontal overflow on small screens", async ({ page, isMobile }) => {
    await page.goto("/materials");
    if (page.url().includes("/login")) return;

    // Body width should match window width without horizontal overflow
    const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
    const windowWidth = await page.evaluate(() => window.innerWidth);
    expect(bodyWidth).toBeLessThanOrEqual(windowWidth + 5);
  });
});

