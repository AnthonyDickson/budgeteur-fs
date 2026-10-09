import { type Page } from '@playwright/test';

import { expectAmount } from '../support/amount';
import { test, expect } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

const tagModal = (page: Page) => page.getByTestId('tag-modal');
const transactionModal = (page: Page) => page.getByTestId('transaction-modal');

/// Today in the browser's timezone as YYYY-MM-DD, so the transactions fall in
/// the dashboard's default "This month" period.
function localToday(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/// Create a tag through the open tag modal, choosing its kind.
async function submitTag(page: Page, name: string, kind: 'Income' | 'Expense') {
  await expect(tagModal(page)).toBeVisible();
  await tagModal(page).getByTestId('tag-name-input').fill(name);
  await tagModal(page).getByTestId(`tag-kind-${kind}`).check();
  await tagModal(page).getByTestId('tag-submit-button').click();
  await expect(tagModal(page)).toBeHidden();
}

async function recordTransaction(
  page: Page,
  args: {
    description: string;
    amount: string;
    credit?: boolean;
    tag?: string;
    isTransfer?: boolean;
  },
) {
  await page.getByTestId('record-transaction-button').click();
  const modal = transactionModal(page);
  await expect(modal).toBeVisible();
  await modal.getByTestId('transaction-amount-input').fill(args.amount);
  if (args.credit) {
    await modal.getByTestId('transaction-type-credit').check();
  }
  if (args.isTransfer) {
    await modal.getByTestId('transaction-is-transfer-input').check();
  }
  await modal.getByTestId('transaction-description-input').fill(args.description);
  await modal.getByTestId('transaction-date-input').fill(localToday());
  if (args.tag) {
    await modal.getByTestId('transaction-tag-select').selectOption({ label: args.tag });
  }
  await modal.getByTestId('transaction-submit-button').click();
  await expect(modal).toBeHidden();
  await expect(
    page.locator('[data-testid="transaction-row"]').filter({ hasText: args.description }),
  ).toHaveCount(1);
}

test.describe('dashboard', () => {
  test('shows the income statement for this month', async ({ page }, testInfo) => {
    await page.goto('/tagging');
    await page.getByTestId('create-first-tag-button').click();
    await submitTag(page, 'Salary', 'Income');
    await page.getByTestId('new-tag-button').click();
    await submitTag(page, 'Groceries', 'Expense');

    await page.goto('/transactions');
    await recordTransaction(page, {
      description: 'Pay',
      amount: '5000.00',
      credit: true,
      tag: 'Salary',
    });
    await recordTransaction(page, { description: 'Supermarket', amount: '300.00', tag: 'Groceries' });
    await recordTransaction(page, {
      description: 'Supermarket refund',
      amount: '50.00',
      credit: true,
      tag: 'Groceries',
    });
    await recordTransaction(page, { description: 'Parking', amount: '25.00' });
    await recordTransaction(page, {
      description: 'To savings',
      amount: '1000.00',
      isTransfer: true,
    });

    await page.getByRole('link', { name: 'Dashboard' }).click();
    await expect(page).toHaveURL(/\/$/);

    // The refund reduces Groceries; the transfer is excluded.
    await expectAmount(page.getByTestId('dashboard-income'), 5000);
    await expectAmount(page.getByTestId('dashboard-expenses'), 275);
    await expectAmount(page.getByTestId('dashboard-net-income'), 4725);

    const expenseLines = page.getByTestId('dashboard-expense-lines').getByTestId('dashboard-line');
    await expect(expenseLines).toHaveCount(2);
    await expect(expenseLines.nth(0)).toContainText('Groceries');
    await expectAmount(expenseLines.nth(0), 250);
    await expect(expenseLines.nth(1)).toContainText('Untagged expenses');
    await expectAmount(expenseLines.nth(1), 25);

    await expect(page.getByTestId('dashboard-untagged-notice')).toContainText('1 transaction');
    await expect(page.getByTestId('dashboard-no-balance-sheet')).toBeVisible();
    await page.screenshot({
      path: screenshotPath(testInfo, 'dashboard-this-month'),
      fullPage: true,
    });

    // Last month has no transactions.
    await page.getByTestId('period-LastMonth').click();
    await expect(page.getByTestId('dashboard-no-transactions')).toBeVisible();

    // The chosen period is remembered across visits.
    await page.reload();
    await expect(page.getByTestId('period-LastMonth')).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByTestId('dashboard-no-transactions')).toBeVisible();
  });
});
