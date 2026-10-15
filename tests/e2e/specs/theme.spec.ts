import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

/// The page background is the flavour's mantle: Catppuccin Latte in light
/// mode and Mocha in dark mode. See decisions 1 and 2 in docs/styling.md.
const pageBackground = {
  light: 'rgb(230, 233, 239)',
  dark: 'rgb(24, 24, 37)',
} as const;

test.describe('theme', () => {
  for (const scheme of ['light', 'dark'] as const) {
    test(`the ${scheme} colour scheme selects its flavour`, async ({
      page,
    }, testInfo) => {
      await page.emulateMedia({ colorScheme: scheme });
      await page.goto('/transactions');
      await expect(page.getByTestId('record-transaction-button')).toBeVisible();

      const background = await page.evaluate(() =>
        getComputedStyle(document.body).backgroundColor
      );
      expect(background).toBe(pageBackground[scheme]);

      await page.screenshot({
        path: screenshotPath(testInfo, `transactions-${scheme}`),
        fullPage: true,
      });
    });
  }
});
