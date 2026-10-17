import { type Locator, type Page } from '@playwright/test';

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

/// The element is wholly on screen once scrolled to, not clipped by a card
/// with overflow hidden.
async function expectFullyOnScreen(locator: Locator) {
  await locator.scrollIntoViewIfNeeded();
  await expect(locator).toBeInViewport({ ratio: 1 });
}

/// Today in the browser's timezone as YYYY-MM-DD, so the transaction falls in
/// the dashboard's month to date.
function localToday(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${
    pad(now.getDate())
  }`;
}

/// Every visible text field is at least 16px, so Safari on iOS does not zoom
/// the page when one is focused. Chromium does not zoom, so the size is checked
/// rather than the zoom.
async function expectFieldsAvoidZoom(page: Page) {
  const small = await page.evaluate(() =>
    Array.from(document.querySelectorAll('input, select, textarea'))
      .filter((field) => {
        const type = field.getAttribute('type');
        return !['checkbox', 'radio', 'file', 'hidden'].includes(type ?? '')
          && field.getClientRects().length > 0;
      })
      .filter((field) => parseFloat(getComputedStyle(field).fontSize) < 16)
      .map((field) => field.getAttribute('data-testid') ?? field.outerHTML)
  );
  expect(small, 'fields smaller than 16px').toEqual([]);
}

/// The first day of the month `monthsAgo` before the browser's current month,
/// as YYYY-MM-DD.
function monthStart(monthsAgo: number): string {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - monthsAgo, 1);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${start.getFullYear()}-${pad(start.getMonth() + 1)}-01`;
}

/// The chart's month labels, those it shows, do not overlap.
async function expectMonthLabelsApart(chart: Locator) {
  const labels = chart.locator('[aria-label="x-axis tick label"] text');
  await expect(labels.first()).toBeAttached();
  const spans = await labels.evaluateAll((elements) =>
    elements
      .filter((element) => element.textContent !== '')
      .map((element) => {
        const box = element.getBoundingClientRect();
        return [box.left, box.right];
      })
  );
  expect(spans.length).toBeGreaterThan(1);
  for (let i = 1; i < spans.length; i++) {
    expect(spans[i][0], 'month labels overlap').toBeGreaterThan(
      spans[i - 1][1],
    );
  }
}

/// The open dialog fits within the screen's width, leaving a margin at each
/// side.
async function expectDialogFits(page: Page, testId: string) {
  const box = (await page.getByTestId(testId).boundingBox())!;
  const width = page.viewportSize()!.width;
  expect(box.x).toBeGreaterThanOrEqual(8);
  expect(box.x + box.width).toBeLessThanOrEqual(width - 8);
}

/// Each help button within `container` is a target of at least 24px square.
async function expectHelpTargets(container: Locator) {
  const buttons = container.locator('[popovertarget]');
  expect(await buttons.count()).toBeGreaterThan(0);
  for (
    const box of await buttons.evaluateAll((elements) =>
      elements.map((element) => element.getBoundingClientRect())
    )
  ) {
    expect(box.width).toBeGreaterThanOrEqual(24);
    expect(box.height).toBeGreaterThanOrEqual(24);
  }
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
      await expectFullyOnScreen(page.getByTestId('toast').first());

      // The rules panel sits under the tags, not clipped beside them.
      const newRule = page.getByTestId('new-rule-button');
      await expectFullyOnScreen(newRule);
      await newRule.click();
      const ruleModal = page.getByTestId('rule-modal');
      await expect(ruleModal).toBeVisible();
      await expectDialogFits(page, 'rule-modal');
      await expectHelpTargets(ruleModal);
      await ruleModal.getByTestId('rule-pattern-input').fill('CLOUDSTORE');
      await ruleModal.getByTestId('rule-submit-button').click();
      await expect(ruleModal).toBeHidden();
      await expectFullyOnScreen(page.getByTestId('rule-row'));
      await expectNoSidewaysScroll(page);
      await page.screenshot({ path: screenshotPath(testInfo, 'tagging') });

      await openFromMenu(page, 'Transactions', /\/transactions$/);
      await page.getByTestId('record-transaction-button').click();
      const transactionModal = page.getByTestId('transaction-modal');
      await expect(transactionModal).toBeVisible();
      await expectDialogFits(page, 'transaction-modal');
      await expectFieldsAvoidZoom(page);
      await page.screenshot({
        path: screenshotPath(testInfo, 'transaction-modal'),
      });
      await transactionModal.getByTestId('transaction-amount-input').fill(
        '23.50',
      );
      await transactionModal.getByTestId('transaction-description-input').fill(
        'POS W/D CLOUDSTORE.COM/BILL SYDNEY AU (INC. $0.31 INTERNATIONAL TRANSACTION FEE)',
      );
      const today = localToday();
      await transactionModal.getByTestId('transaction-date-input').fill(today);
      await transactionModal.getByTestId('transaction-tag-select')
        .selectOption({ label: 'Subscriptions' });
      await transactionModal.getByTestId('transaction-submit-button').click();
      await expect(transactionModal).toBeHidden();
      const row = page.getByTestId('transaction-row');
      await expect(row).toHaveCount(1);
      await expectNoSidewaysScroll(page);
      // The row's figures are on screen, not clipped by the list's card.
      for (const text of ['-$23.50', today, 'Subscriptions']) {
        await expectFullyOnScreen(
          row.getByText(text).filter({ visible: true }),
        );
      }
      await page.screenshot({
        path: screenshotPath(testInfo, 'transactions'),
        fullPage: true,
      });

      // A transaction 11 months ago fills the dashboard's year of history.
      await page.getByTestId('record-transaction-button').click();
      await expect(transactionModal).toBeVisible();
      await transactionModal.getByTestId('transaction-amount-input').fill(
        '40.00',
      );
      await transactionModal.getByTestId('transaction-description-input').fill(
        'CLOUDSTORE.COM/BILL',
      );
      await transactionModal.getByTestId('transaction-date-input').fill(
        monthStart(11),
      );
      await transactionModal.getByTestId('transaction-submit-button').click();
      await expect(transactionModal).toBeHidden();
      await expect(row).toHaveCount(2);
      await page.getByTestId('filters-button').click();
      await expect(page.getByTestId('dates-select')).toBeVisible();
      await expectFieldsAvoidZoom(page);

      // The dashboard's tag table and monthly figures fit their cards.
      await openFromMenu(page, 'Dashboard', /\/$/);
      await expectNoSidewaysScroll(page);
      const line = page.getByTestId('dashboard-line').filter({
        hasText: 'Subscriptions',
      });
      await expectFullyOnScreen(line.getByText('Subscriptions'));
      await expectFullyOnScreen(line.locator('[data-amount]'));
      await expectMonthLabelsApart(
        page.getByTestId('dashboard-cash-flow-chart'),
      );
      await page.getByTestId('dashboard-cash-flow-toggle').click();
      await expectFullyOnScreen(
        page.getByTestId('dashboard-cash-flow').locator('th').last(),
      );
      await page.screenshot({
        path: screenshotPath(testInfo, 'dashboard'),
        fullPage: true,
      });

      // An account named by its number, which cannot wrap, with a balance
      // in the month the report shows.
      await openFromMenu(page, 'Balance Sheet', /\/balance-sheet$/);
      await page.getByTestId('add-account-button').click();
      const accountModal = page.getByTestId('account-modal');
      await expect(accountModal).toBeVisible();
      await expectDialogFits(page, 'account-modal');
      await accountModal.getByTestId('account-name-input').fill(
        '38-9024-0573525-000',
      );
      await accountModal.getByTestId('balance-amount-input').fill('8056.89');
      await accountModal.getByTestId('balance-as-of-input').fill(monthStart(1));
      await accountModal.getByTestId('account-submit-button').click();
      await expect(accountModal).toBeHidden();
      await expectNoSidewaysScroll(page);
      await page.screenshot({
        path: screenshotPath(testInfo, 'balance-sheet'),
        fullPage: true,
      });

      // The report's balance sheet keeps its amounts inside the card.
      await openFromMenu(page, 'Reports', /\/reports$/);
      await expectNoSidewaysScroll(page);
      await expectFieldsAvoidZoom(page);
      const sheet = page.getByTestId('report-sheet-lines');
      await expectFullyOnScreen(sheet.getByText('Amount'));
      await expectFullyOnScreen(sheet.locator('[data-amount]').first());
      await page.screenshot({
        path: screenshotPath(testInfo, 'reports'),
        fullPage: true,
      });

      await page.getByTestId('nav-menu-button').click();
      await expect(menu(page)).toBeVisible();
      await expectFullyOnScreen(
        menu(page).getByTestId('nav-menu-log-out-button'),
      );
      await page.screenshot({ path: screenshotPath(testInfo, 'menu') });

      await page.goto('/signed-out');
      await expect(page.getByTestId('signed-out-page')).toBeVisible();
      await expectNoSidewaysScroll(page);
      await page.screenshot({ path: screenshotPath(testInfo, 'signed-out') });
    },
  );
});
