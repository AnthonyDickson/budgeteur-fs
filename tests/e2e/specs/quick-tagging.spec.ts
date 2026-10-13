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

/// Record an untagged transaction from the transactions page.
async function recordTransaction(page: Page, description: string) {
  await page.goto('/transactions');
  await page.getByTestId('record-transaction-button').click();
  const modal = page.getByTestId('transaction-modal');
  await expect(modal).toBeVisible();
  await modal.getByTestId('transaction-amount-input').fill('10.00');
  await modal.getByTestId('transaction-description-input').fill(description);
  await modal.getByTestId('transaction-date-input').fill('2026-10-01');
  await modal.getByTestId('transaction-submit-button').click();
  await expect(modal).toBeHidden();
}

const queueRow = (page: Page, description: string) =>
  page.getByTestId('quick-tag-row').filter({ hasText: description });

test.describe('quick tagging', () => {
  test('tags and dismisses transactions with one click each', async ({
    page,
  }, testInfo) => {
    await createFirstTag(page, 'Groceries');
    await recordTransaction(page, 'Countdown');
    await recordTransaction(page, 'ATM withdrawal');

    await page.getByTestId('quick-tag-link').click();
    await expect(page.getByTestId('quick-tag-waiting')).toHaveText(
      '2 transactions are waiting for a tag',
    );

    // Found by role and name: the choices are native buttons, which Vimium's
    // link hints find.
    const groceries = queueRow(page, 'Countdown').getByRole('button', {
      name: 'Groceries',
    });
    await groceries.click();
    await expect(groceries).toHaveAttribute('aria-pressed', 'true');

    const dismiss = queueRow(page, 'ATM withdrawal').getByRole('button', {
      name: 'Dismiss',
    });
    await dismiss.click();
    await expect(dismiss).toHaveAttribute('aria-pressed', 'true');

    await expect(page.getByTestId('quick-tag-waiting')).toHaveText(
      '0 transactions are waiting for a tag',
    );
    await page.screenshot({
      path: screenshotPath(testInfo, 'quick-tagged'),
      fullPage: true,
    });

    await page.reload();
    await expect(page.getByTestId('quick-tag-empty-state')).toBeVisible();

    await page.goto('/transactions');
    await expect(
      page
        .locator('[data-testid="transaction-row"]')
        .filter({ hasText: 'Countdown' }),
    ).toContainText('Groceries');
  });
});
