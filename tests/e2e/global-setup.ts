import { chromium, type FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  const { baseURL, ignoreHTTPSErrors } = config.projects[0].use;
  const browser = await chromium.launch();
  const context = await browser.newContext({ ignoreHTTPSErrors });
  const page = await context.newPage();

  try {
    // TODO: Revert to just baseURL once dashboard makes request to protected route
    // HACK: Use transactions page to trigger auth redirect
    await page.goto(baseURL! + "/transactions");

    // SPA detects 401, redirects to /login, OIDC challenge lands on Authelia
    await page.waitForURL('**127.0.0.1:9091**');

    // Wait for MUI login form to hydrate
    await page.waitForSelector('#username-textfield', { state: 'visible' });
    await page.waitForSelector('#password-textfield', { state: 'visible' });
    await page.waitForTimeout(500);

    // Use click + pressSequentially for MUI controlled inputs
    const username = page.locator('#username-textfield');
    await username.click();
    await username.pressSequentially('dev', { delay: 50 });
    const password = page.locator('#password-textfield');
    await password.click();
    await password.pressSequentially('dev-password', { delay: 50 });
    await page.click('#sign-in-button');

    // Consent screen appears on first login only
    const consentAccept = page.locator('#openid-consent-accept');
    const hasConsent = await consentAccept
      .waitFor({ state: 'visible', timeout: 8000 })
      .then(() => true)
      .catch(() => false);
    if (hasConsent) {
      await consentAccept.click();
    }
    await page.waitForURL('**localhost:5173**', { timeout: 15000 });

    await context.storageState({ path: 'auth.json' });
  } catch (e) {
    await page.screenshot({ path: 'test-results/global-setup-failure.png', fullPage: true });
    throw e;
  } finally {
    await browser.close();
  }
}

export default globalSetup;
