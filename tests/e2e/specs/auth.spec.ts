import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

test.describe('auth', () => {
  test(
    'the signed out page signs back in',
    async ({ page }, testInfo) => {
      await page.goto('/signed-out');
      await expect(page.getByTestId('signed-out-page')).toBeVisible();
      await expect(page).toHaveTitle('Signed out | Budgeteur');
      await expect(page.locator('header')).toHaveCount(0);
      await page.screenshot({ path: screenshotPath(testInfo, 'signed-out') });

      // The session is still live, so signing in needs no login form.
      await page.getByTestId('sign-in-button').click();
      await expect(page).toHaveTitle('Dashboard | Budgeteur');
    },
  );
});
