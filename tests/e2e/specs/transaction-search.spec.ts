import { type Page } from '@playwright/test';

import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

/// Create the first tag through the tagging UI. Each test starts with no data
/// (see support/fixtures.ts), so the tagging page shows the empty state.
async function createFirstTag(page: Page, name: string) {
  await page.goto('/tagging');
  await page.getByTestId('create-first-tag-button').click();

  const modal = page.getByTestId('tag-modal');
  await expect(modal).toBeVisible();
  await modal.getByTestId('tag-name-input').fill(name);
  await modal.getByTestId('tag-submit-button').click();
  await expect(modal).toBeHidden();
}

/// Record a transaction from the transactions page, with the tag if given.
async function recordTransaction(
  page: Page,
  description: string,
  tagName?: string,
) {
  await page.getByTestId('record-transaction-button').click();
  const modal = page.getByTestId('transaction-modal');
  await expect(modal).toBeVisible();
  await modal.getByTestId('transaction-amount-input').fill('10.00');
  await modal.getByTestId('transaction-description-input').fill(description);
  await modal.getByTestId('transaction-date-input').fill('2026-10-01');
  if (tagName) {
    await modal
      .getByTestId('transaction-tag-select')
      .selectOption({ label: tagName });
  }
  await modal.getByTestId('transaction-submit-button').click();
  await expect(modal).toBeHidden();
}

const rows = (page: Page) => page.getByTestId('transaction-row');

test.describe('transaction search', () => {
  test(
    'searches by text, narrows by tag, keeps edited rows, and clears',
    async ({
      page,
    }, testInfo) => {
      await createFirstTag(page, 'Groceries');
      await page.goto('/transactions');
      await recordTransaction(page, 'Countdown Auckland', 'Groceries');
      await recordTransaction(page, 'COUNTDOWN METRO');
      await recordTransaction(page, 'New World', 'Groceries');
      await expect(rows(page)).toHaveCount(3);

      // ── Search by text ───────────────────────────────────────────────────────
      // Matching ignores case, like rules.
      await page.getByTestId('search-input').fill('countdown');
      await expect(rows(page)).toHaveCount(2);
      await expect(rows(page).filter({ hasText: 'New World' })).toHaveCount(0);

      // ── Narrow by tag ────────────────────────────────────────────────────────
      await page.getByTestId('filters-button').click();
      await page
        .getByTestId('tag-select')
        .selectOption({ label: 'Groceries' });
      await expect(rows(page)).toHaveCount(1);
      await expect(rows(page)).toContainText('Countdown Auckland');
      await expect(page.getByTestId('filters-button')).toHaveText(
        'Filters (1)',
      );
      await page.screenshot({
        path: screenshotPath(testInfo, 'search-narrowed'),
        fullPage: true,
      });

      // ── Edit a match so it no longer matches ─────────────────────────────────
      // The row stays, so the user sees the edit, until the next search.
      await rows(page).filter({ hasText: 'Countdown Auckland' }).click();
      const modal = page.getByTestId('transaction-modal');
      await expect(modal).toBeVisible();
      await modal
        .getByTestId('transaction-description-input')
        .fill("Pak'nSave");
      await modal.getByTestId('transaction-submit-button').click();
      await expect(modal).toBeHidden();
      await expect(rows(page)).toHaveCount(1);
      await expect(rows(page)).toContainText("Pak'nSave");

      // ── Clear ────────────────────────────────────────────────────────────────
      await page.getByTestId('clear-search-button').click();
      await expect(page.getByTestId('search-input')).toHaveValue('');
      await expect(page.getByTestId('filters-button')).toHaveText('Filters');
      await expect(rows(page)).toHaveCount(3);
      await page.screenshot({
        path: screenshotPath(testInfo, 'search-cleared'),
        fullPage: true,
      });
    },
  );

  test('says when nothing matches', async ({ page }) => {
    await page.goto('/transactions');
    await recordTransaction(page, 'Countdown');

    await page.getByTestId('search-input').fill('no such shop');
    await expect(page.getByTestId('no-matches-empty-state')).toBeVisible();

    await page.getByTestId('clear-search-empty-button').click();
    await expect(rows(page)).toHaveCount(1);
  });
});
