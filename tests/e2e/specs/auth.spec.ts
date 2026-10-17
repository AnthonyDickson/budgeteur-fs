import { expect, logIn, test, workerUser } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

/// Authelia's login form, which shows only without a provider session.
const providerLogin = '#username-textfield';

test.describe('auth', () => {
  test(
    'a login returns to its page, and logging out ends the provider session',
    async ({ browser, baseURL }, testInfo) => {
      // A session of its own, since logging out ends the provider session the
      // worker's other tests share. A new context takes the worker's saved
      // session unless told otherwise.
      const context = await browser.newContext({
        baseURL,
        ignoreHTTPSErrors: true,
        storageState: { cookies: [], origins: [] },
      });
      const page = await context.newPage();

      try {
        await logIn(page, baseURL!, workerUser(testInfo.parallelIndex));
        // The login returns to the page that asked for it.
        await expect(page).toHaveURL(/\/transactions$/);
        await page.goto('/');
        await page.getByTestId('log-out-button').click();

        // The dev app is served over http, so Authelia does not return to it
        // and shows its login form.
        await page.waitForURL('**127.0.0.1:9091**');
        await expect(page.locator(providerLogin)).toBeVisible();

        // The app asks for a login again, rather than signing straight back in.
        await page.goto('/');
        await page.waitForURL('**127.0.0.1:9091**');
        await expect(page.locator(providerLogin)).toBeVisible();
        await page.screenshot({
          path: screenshotPath(testInfo, 'login-after-logout'),
        });
      } finally {
        await context.close();
      }
    },
  );

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
