import { type Page } from '@playwright/test';

import { expectAmount } from '../support/amount';
import { test, expect } from '../support/fixtures';
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

test.describe('transactions', () => {
  test('full CRUD flow for a transaction', async ({ page }, testInfo) => {
    const description = 'Coffee';
    const tagName = 'Groceries';

    await createFirstTag(page, tagName);
    await page.goto('/transactions');
    const emptyState = page.getByTestId('no-transactions-empty-state');
    await expect(emptyState).toBeVisible();

    // ── Create ───────────────────────────────────────────────────────────────
    await page.getByTestId('record-transaction-button').click();

    const formModal = page.getByTestId('transaction-modal');
    await expect(formModal).toBeVisible();
    await formModal.getByTestId('transaction-amount-input').fill('12.34');
    await formModal
      .getByTestId('transaction-description-input')
      .fill(description);
    await formModal.getByTestId('transaction-date-input').fill('2026-08-15');
    const tagSelect = formModal.getByTestId('transaction-tag-select');
    await tagSelect.selectOption({ label: tagName });
    const tagValue = await tagSelect.inputValue();
    await formModal.getByTestId('transaction-submit-button').click();

    // Debit is the default type, so the amount is shown as negative.
    const row = page
      .locator('[data-testid="transaction-row"]')
      .filter({ hasText: description });
    await expect(row).toHaveCount(1);
    await expectAmount(row, -12.34);
    await expect(row).toContainText('2026-08-15');
    await expect(row).toContainText(tagName);
    await expect(formModal).toBeHidden();
    await expect(emptyState).toBeHidden();
    await page.screenshot({
      path: screenshotPath(testInfo, 'transaction-created'),
      fullPage: true,
    });

    // ── Update ───────────────────────────────────────────────────────────────
    const updatedDescription = `${description} (updated)`;

    await row.getByRole('button', { name: 'Edit' }).click();
    await expect(formModal).toBeVisible();
    const editTagSelect = formModal.getByTestId('transaction-tag-select');
    await expect(editTagSelect).toHaveValue(tagValue);
    await formModal.getByTestId('transaction-amount-input').fill('25.00');
    await formModal
      .getByTestId('transaction-description-input')
      .fill(updatedDescription);
    await editTagSelect.selectOption('');
    await formModal.getByTestId('transaction-submit-button').click();

    const updatedRow = page
      .locator('[data-testid="transaction-row"]')
      .filter({ hasText: updatedDescription });
    await expect(updatedRow).toHaveCount(1);
    await expectAmount(updatedRow, -25.0);
    await expect(updatedRow).toContainText('2026-08-15');
    await expect(updatedRow).not.toContainText(tagName);
    await expect(formModal).toBeHidden();
    await page.screenshot({
      path: screenshotPath(testInfo, 'transaction-updated'),
      fullPage: true,
    });

    // ── Delete ───────────────────────────────────────────────────────────────
    const rowToDelete = updatedRow;
    await rowToDelete.getByRole('button', { name: 'Delete' }).click();

    const deleteModal = page.getByTestId('delete-transaction-modal');
    await expect(deleteModal).toBeVisible();
    await deleteModal.getByTestId('delete-confirm-button').click();

    await expect(rowToDelete).toHaveCount(0);
    await expect(emptyState).toBeVisible();
    await page.screenshot({
      path: screenshotPath(testInfo, 'transaction-deleted'),
      fullPage: true,
    });
  });
});
