import { test, expect } from '@playwright/test';

test.describe('transactions', () => {
  test('full CRUD flow for a transaction', async ({ page }, testInfo) => {
    // Playwright reuses the same per-test output folder across retries, so the
    // retry number is folded into the filename to keep each attempt's
    // screenshots.
    const screenshotPath = (name: string) =>
      testInfo.outputPath(
        `${name}${testInfo.retry > 0 ? `.retry-${testInfo.retry}` : ''}.png`,
      );
    // A unique description keeps retries independent: the database persists
    // across attempts within a single `just e2e-test` run.
    const description = `E2E transaction ${Date.now()}`;

    await page.goto('/transactions');

    // ── Create ───────────────────────────────────────────────────────────────
    await page.getByTestId('record-transaction-button').click();

    const formModal = page.getByTestId('transaction-modal');
    await expect(formModal).toBeVisible();
    await formModal.getByTestId('transaction-amount-input').fill('12.34');
    await formModal
      .getByTestId('transaction-description-input')
      .fill(description);
    await formModal.getByTestId('transaction-date-input').fill('2026-08-15');
    await formModal.getByTestId('transaction-submit-button').click();

    // Debit is the default type, so the amount is shown as negative.
    const row = page
      .locator('[data-testid="transaction-row"]')
      .filter({ hasText: description });
    await expect(row).toHaveCount(1);
    await expect(row).toContainText('-$12.34');
    await expect(row).toContainText('2026-08-15');
    await expect(formModal).toBeHidden();
    await page.screenshot({
      path: screenshotPath('transaction-created'),
      fullPage: true,
    });

    // ── Update ───────────────────────────────────────────────────────────────
    const updatedDescription = `${description} (updated)`;

    await row.getByRole('button', { name: 'Edit' }).click();
    await expect(formModal).toBeVisible();
    await formModal.getByTestId('transaction-amount-input').fill('25.00');
    await formModal
      .getByTestId('transaction-description-input')
      .fill(updatedDescription);
    await formModal.getByTestId('transaction-submit-button').click();

    const updatedRow = page
      .locator('[data-testid="transaction-row"]')
      .filter({ hasText: updatedDescription });
    await expect(updatedRow).toHaveCount(1);
    await expect(updatedRow).toContainText('-$25.00');
    await expect(updatedRow).toContainText('2026-08-15');
    await expect(formModal).toBeHidden();
    await page.screenshot({
      path: screenshotPath('transaction-updated'),
      fullPage: true,
    });

    // ── Delete ───────────────────────────────────────────────────────────────
    const rowToDelete = updatedRow;
    await rowToDelete.getByRole('button', { name: 'Delete' }).click();

    const deleteModal = page.getByTestId('delete-transaction-modal');
    await expect(deleteModal).toBeVisible();
    await deleteModal.getByTestId('delete-confirm-button').click();

    await expect(rowToDelete).toHaveCount(0);
    await page.screenshot({
      path: screenshotPath('transaction-deleted'),
      fullPage: true,
    });
  });
});
