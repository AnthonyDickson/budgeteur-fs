import { type Page } from '@playwright/test';

import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

/// The narrowest supported phone: a 6.1" iPhone (iPhone 12 to 14) in
/// Safari, which leaves 390 by 664 CSS pixels for the page.
test.use({
  viewport: { width: 390, height: 664 },
  deviceScaleFactor: 3,
  isMobile: true,
  hasTouch: true,
});

const menu = (page: Page) => page.getByTestId('nav-menu');

/// Go to a page through the header's menu, which closes once the page opens.
async function openFromMenu(page: Page, name: string, url: RegExp) {
  await page.getByTestId('nav-menu-button').click();
  await expect(menu(page)).toBeVisible();
  await menu(page).getByRole('link', { name }).click();
  await expect(page).toHaveURL(url);
  await expect(menu(page)).toBeHidden();
}

/// The page fits the screen's width, so it never scrolls sideways.
async function expectNoSidewaysScroll(page: Page) {
  const { scrollWidth, clientWidth } = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));
  expect(scrollWidth, 'the page is wider than the screen').toBe(clientWidth);
}

/// The open dialog fits within the screen's width.
async function expectDialogFits(page: Page, testId: string) {
  const box = await page.getByTestId(testId).boundingBox();
  const width = page.viewportSize()!.width;
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.x + box!.width).toBeLessThanOrEqual(width);
}

test.describe('mobile', () => {
  test(
    'every page fits a phone and the menu opens each one',
    async ({ page }, testInfo) => {
      await page.goto('/');
      await expect(page.getByRole('heading', { name: 'Dashboard' }))
        .toBeVisible();

      // Tag a transaction with a long description, so the pages have rows
      // and figures to lay out.
      await openFromMenu(page, 'Tags & Rules', /\/tagging$/);
      await page.getByTestId('create-first-tag-button').click();
      const tagModal = page.getByTestId('tag-modal');
      await expect(tagModal).toBeVisible();
      await expectDialogFits(page, 'tag-modal');
      await tagModal.getByTestId('tag-name-input').fill('Subscriptions');
      await tagModal.getByTestId('tag-submit-button').click();
      await expect(tagModal).toBeHidden();
      await expectNoSidewaysScroll(page);
      await page.screenshot({ path: screenshotPath(testInfo, 'tagging') });

      await openFromMenu(page, 'Transactions', /\/transactions$/);
      await page.getByTestId('record-transaction-button').click();
      const transactionModal = page.getByTestId('transaction-modal');
      await expect(transactionModal).toBeVisible();
      await expectDialogFits(page, 'transaction-modal');
      await page.screenshot({
        path: screenshotPath(testInfo, 'transaction-modal'),
      });
      await transactionModal.getByTestId('transaction-amount-input').fill(
        '23.50',
      );
      await transactionModal.getByTestId('transaction-description-input').fill(
        'POS W/D CLOUDSTORE.COM/BILL SYDNEY AU (INC. $0.31 INTERNATIONAL TRANSACTION FEE)',
      );
      await transactionModal.getByTestId('transaction-date-input').fill(
        '2026-10-01',
      );
      await transactionModal.getByTestId('transaction-tag-select')
        .selectOption({ label: 'Subscriptions' });
      await transactionModal.getByTestId('transaction-submit-button').click();
      await expect(transactionModal).toBeHidden();
      const row = page.getByTestId('transaction-row');
      await expect(row).toHaveCount(1);
      await expectNoSidewaysScroll(page);
      // The row's figures are on screen, not clipped by the list's card.
      for (const text of ['-$23.50', '2026-10-01', 'Subscriptions']) {
        await expect(row.getByText(text).filter({ visible: true }))
          .toBeInViewport({ ratio: 1 });
      }
      await page.screenshot({
        path: screenshotPath(testInfo, 'transactions'),
        fullPage: true,
      });

      for (
        const [name, url, shot] of [
          ['Dashboard', /\/$/, 'dashboard'],
          ['Reports', /\/reports$/, 'reports'],
          ['Balance Sheet', /\/balance-sheet$/, 'balance-sheet'],
        ] as const
      ) {
        await openFromMenu(page, name, url);
        await expectNoSidewaysScroll(page);
        await page.screenshot({
          path: screenshotPath(testInfo, shot),
          fullPage: true,
        });
      }

      await page.getByTestId('nav-menu-button').click();
      await expect(menu(page)).toBeVisible();
      await page.screenshot({ path: screenshotPath(testInfo, 'menu') });
    },
  );
});
