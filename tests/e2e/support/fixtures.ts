import fs from 'node:fs';
import path from 'node:path';

import { test as base, expect, type Browser } from '@playwright/test';

/// The number of Authelia users `e2e-0` … `e2e-<n-1>` in `authelia/users.yml`.
/// Each parallel worker logs in as its own user, so this must be at least the
/// `workers` setting in `playwright.config.ts`.
const userCount = 4;

/// Log in as `username` through the SPA's OIDC redirect to Authelia and save
/// the resulting session to `storagePath`.
async function logIn(
  browser: Browser,
  baseURL: string,
  username: string,
  storagePath: string,
) {
  const context = await browser.newContext({ baseURL, ignoreHTTPSErrors: true });
  const page = await context.newPage();

  try {
    // HACK: Use transactions page to trigger auth redirect
    await page.goto('/transactions');

    // SPA detects 401, redirects to /login, OIDC challenge lands on Authelia
    await page.waitForURL('**127.0.0.1:9091**');

    // Wait for MUI login form to hydrate
    await page.waitForSelector('#username-textfield', { state: 'visible' });
    await page.waitForSelector('#password-textfield', { state: 'visible' });
    await page.waitForTimeout(500);

    // Use click + pressSequentially for MUI controlled inputs
    const usernameInput = page.locator('#username-textfield');
    await usernameInput.click();
    await usernameInput.pressSequentially(username, { delay: 50 });
    const passwordInput = page.locator('#password-textfield');
    await passwordInput.click();
    await passwordInput.pressSequentially('dev-password', { delay: 50 });
    await page.click('#sign-in-button');

    // Consent screen appears on a user's first login only
    const consentAccept = page.locator('#openid-consent-accept');
    const hasConsent = await consentAccept
      .waitFor({ state: 'visible', timeout: 8000 })
      .then(() => true)
      .catch(() => false);
    if (hasConsent) {
      await consentAccept.click();
    }
    await page.waitForURL(`${baseURL}/**`, { timeout: 15000 });

    await context.storageState({ path: storagePath });
  } catch (e) {
    await page.screenshot({
      path: storagePath.replace(/\.json$/, '-login-failure.png'),
      fullPage: true,
    });
    throw e;
  } finally {
    await context.close();
  }
}

/// The suite's `test`. Specs import `test` and `expect` from here, not from
/// `@playwright/test`, so every test is isolated:
///
/// - Each parallel worker logs in as its own user, and the server scopes all
///   data by user, so workers never see each other's data.
/// - Each test starts by deleting its user's data, so tests in the same worker
///   (and retries) never see each other's data either.
export const test = base.extend<{ resetUserData: void }, { workerStorageState: string }>({
  storageState: ({ workerStorageState }, use) => use(workerStorageState),

  workerStorageState: [
    async ({ browser }, use, workerInfo) => {
      // `parallelIndex` is reused by a worker that restarts after a failure,
      // unlike `workerIndex`, so it maps to the same user and saved session.
      const index = workerInfo.parallelIndex;
      if (index >= userCount) {
        throw new Error(
          `Worker ${index} has no E2E user: add users to authelia/users.yml and raise userCount, or lower workers`,
        );
      }

      const storagePath = path.resolve(workerInfo.project.outputDir, '.auth', `${index}.json`);
      if (!fs.existsSync(storagePath)) {
        fs.mkdirSync(path.dirname(storagePath), { recursive: true });
        await logIn(browser, workerInfo.project.use.baseURL!, `e2e-${index}`, storagePath);
      }
      await use(storagePath);
    },
    { scope: 'worker' },
  ],

  resetUserData: [
    async ({ page }, use) => {
      // A dev-only endpoint (registered only in Development) that deletes all
      // of the current user's data.
      const response = await page.request.delete('/api/test/user-data');
      expect(response.status()).toBe(204);
      await use();
    },
    { auto: true },
  ],
});

export { expect };
