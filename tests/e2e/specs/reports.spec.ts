import { type Page } from '@playwright/test';

import { expectAmount } from '../support/amount';
import { expect, test } from '../support/fixtures';

/// The first day of the month `monthsAgo` before the browser's current month,
/// as YYYY-MM-DD, and its name as the server labels it, e.g. "March 2026".
function monthStart(monthsAgo: number): { date: string; label: string } {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - monthsAgo, 1);
  const pad = (n: number) => String(n).padStart(2, '0');
  return {
    date: `${start.getFullYear()}-${pad(start.getMonth() + 1)}-01`,
    label: start.toLocaleString('en-US', { month: 'long', year: 'numeric' }),
  };
}

const card = (page: Page, testId: string) => page.getByTestId(testId);

test.describe('reports', () => {
  test('a report splits the change in net worth', async ({ page }) => {
    const twoMonthsAgo = monthStart(2);
    const lastMonth = monthStart(1);

    // A house first valued two months ago and revalued last month.
    await page.goto('/balance-sheet');
    await page.getByTestId('add-asset-button').click();
    const itemModal = page.getByTestId('balance-sheet-item-modal');
    await itemModal.getByTestId('item-name-input').fill('House');
    await itemModal.getByTestId('value-amount-input').fill('400000.00');
    await itemModal.getByTestId('value-as-of-input').fill(twoMonthsAgo.date);
    await itemModal.getByTestId('item-submit-button').click();
    await expect(itemModal).toBeHidden();

    const row = page.locator('[data-testid^="balance-sheet-item-"]').filter({
      hasText: 'House',
    });
    await row.getByTestId(/^record-value-item-/).click();
    const valueModal = page.getByTestId('value-modal');
    await valueModal.getByTestId('value-amount-input').fill('410000.00');
    await valueModal.getByTestId('value-as-of-input').fill(lastMonth.date);
    await valueModal.getByTestId('value-submit-button').click();
    await expect(valueModal).toBeHidden();

    // The reports page opens on the latest complete month.
    await page.goto('/reports');
    await expect(page.getByTestId('report-label')).toHaveText(
      lastMonth.label,
    );
    await expectAmount(card(page, 'report-opening-net-worth'), 400000);
    await expectAmount(card(page, 'report-closing-net-worth'), 410000);
    await expectAmount(card(page, 'report-change-in-net-worth'), 10000);
    await expectAmount(card(page, 'report-other-changes'), 10000);
    await expect(page.getByTestId('report-next')).toBeEnabled();

    // The month before is the first with data: its change is not meaningful,
    // and there is nothing before it.
    await page.getByTestId('report-previous').click();
    await expect(page.getByTestId('report-label')).toHaveText(
      twoMonthsAgo.label,
    );
    await expect(card(page, 'report-change-in-net-worth')).toContainText(
      'Not meaningful',
    );
    await expect(page.getByTestId('report-previous')).toBeDisabled();

    // Another frequency shows its own latest report.
    await page.getByTestId('report-frequency').selectOption('CalendarYear');
    await expect(page.getByTestId('report-label')).toHaveText(/^\d{4}$/);
  });
});
