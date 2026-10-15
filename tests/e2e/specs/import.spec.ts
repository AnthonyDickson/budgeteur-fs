import path from 'node:path';

import { type Page } from '@playwright/test';

import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

/// The anonymised bank exports the server tests use. Docker Compose mounts
/// them at CSV_FIXTURES; outside Docker they are read from the repository.
const fixtures = process.env.CSV_FIXTURES
  ?? path.resolve(
    __dirname,
    '../../../server/tests/Budgeteur.Tests/Import/Fixtures',
  );

const importModal = (page: Page) => page.getByTestId('import-modal');

const transactionRows = (page: Page, description: string) =>
  page.locator('[data-testid="transaction-row"]').filter({
    hasText: description,
  });

test.describe('import', () => {
  test(
    'imports related statements with their accounts and transfers',
    async ({ page }, testInfo) => {
      await page.goto('/transactions');
      await expect(page.getByTestId('no-transactions-empty-state'))
        .toBeVisible();

      await page.getByTestId('import-button').click();
      await expect(importModal(page)).toBeVisible();
      await importModal(page).getByTestId('import-file-input').setInputFiles([
        path.join(fixtures, 'KiwibankChequing.csv'),
        path.join(fixtures, 'KiwibankSavings.csv'),
      ]);
      await importModal(page).getByTestId('import-submit-button').click();
      await expect(importModal(page)).toBeHidden();

      // The toast reports the counts and the accounts the import created.
      await expect(page.getByText('Imported 218 transactions')).toBeVisible();
      await expect(page.getByText('Created accounts:')).toContainText(
        '12-3456-0789012-001',
      );

      // Every row is listed with its account, a page of 100 at a time;
      // transfers are marked.
      const rows = page.locator('[data-testid="transaction-row"]');
      await expect(rows).toHaveCount(100);
      await page.getByTestId('load-more-button').click();
      await expect(rows).toHaveCount(200);
      await page.getByTestId('load-more-button').click();
      await expect(rows).toHaveCount(218);
      await expect(page.getByTestId('load-more-button')).toBeHidden();
      const transfer = transactionRows(page, 'TRANSFER TO A N OTHER - 00')
        .first();
      await expect(transfer).toContainText('12-3456-0789012-001');
      await expect(transfer).toContainText('Transfer');

      await page.screenshot({
        path: screenshotPath(testInfo, 'imported'),
        fullPage: true,
      });

      // Importing the same statement again skips every row.
      await page.getByTestId('import-button').click();
      await importModal(page).getByTestId('import-file-input').setInputFiles(
        path.join(fixtures, 'KiwibankSavings.csv'),
      );
      await importModal(page).getByTestId('import-submit-button').click();
      await expect(page.getByText('Skipped 26 already imported')).toBeVisible();

      // Both accounts are on the balance sheet with their statement balances.
      await page.goto('/balance-sheet');
      const accountLines = page.locator(
        '[data-testid^="balance-sheet-account-"]',
      );
      await expect(accountLines).toHaveCount(2);
      await expect(accountLines.filter({ hasText: '12-3456-0789012-000' }))
        .toContainText('2026-06-26');
    },
  );

  test('lists every problem with a file it cannot read', async ({ page }) => {
    await page.goto('/transactions');
    await page.getByTestId('import-button').click();
    await importModal(page).getByTestId('import-file-input').setInputFiles({
      name: 'notes.csv',
      mimeType: 'text/csv',
      buffer: Buffer.from('Date,Payee,Amount\n2026-03-01,Cafe,-4.50\n'),
    });
    await importModal(page).getByTestId('import-submit-button').click();

    const errors = importModal(page).getByTestId('import-errors');
    await expect(errors).toContainText('notes.csv: matches no known format');
    await expect(errors).toContainText('Date,Payee,Amount');
    await expect(page.getByTestId('no-transactions-empty-state'))
      .toBeVisible();
  });
});
