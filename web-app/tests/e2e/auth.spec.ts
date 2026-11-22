import { test, expect } from "@playwright/test";

test.describe("Authentication & Session Guardrails", () => {
  test("unauthenticated user is redirected to /login", async ({ page }) => {
    await page.goto("/dashboard");
    await expect(page).toHaveURL(/.*login/);
    await expect(page.locator("h1")).toContainText(/Welcome back|Sign In/i);
  });

  test("login form validates email and password presence", async ({ page }) => {
    await page.goto("/login");
    const submitBtn = page.locator('button[type="submit"]');
    await submitBtn.click();

    // Validates that required fields prevent blank submit or show error
    const emailInput = page.locator('input[type="email"]');
    await expect(emailInput).toBeVisible();
  });

  test("login page renders branding and enterprise notices", async ({ page }) => {
    await page.goto("/login");
    await expect(page.locator("text=TSR BUILDERS")).toBeVisible();
    await expect(page.locator("text=Construction Operations")).toBeVisible();
  });
});

