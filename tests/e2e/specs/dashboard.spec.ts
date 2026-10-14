import { type Page } from '@playwright/test';

import { expectAmount } from '../support/amount';
import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

const tagModal = (page: Page) => page.getByTestId('tag-modal');
const transactionModal = (page: Page) => page.getByTestId('transaction-modal');

/// Today in the browser's timezone as YYYY-MM-DD, so the transactions fall in
/// the dashboard's month to date.
function localToday(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${
    pad(now.getDate())
  }`;
}

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
    date?: string;
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
  await modal.getByTestId('transaction-description-input').fill(
    args.description,
  );
  await modal.getByTestId('transaction-date-input').fill(
    args.date ?? localToday(),
  );
  if (args.tag) {
    await modal.getByTestId('transaction-tag-select').selectOption({
      label: args.tag,
    });
  }
  await modal.getByTestId('transaction-submit-button').click();
  await expect(modal).toBeHidden();
  await expect(
    page.locator('[data-testid="transaction-row"]').filter({
      hasText: args.description,
    }),
  ).toHaveCount(1);
}

test.describe('dashboard', () => {
  test(
    'shows the month to date',
    async ({ page }, testInfo) => {
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
      await recordTransaction(page, {
        description: 'Supermarket',
        amount: '300.00',
        tag: 'Groceries',
      });
      await recordTransaction(page, {
        description: 'Supermarket refund',
        amount: '50.00',
        credit: true,
        tag: 'Groceries',
      });
      await recordTransaction(page, {
        description: 'Parking',
        amount: '25.00',
      });
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

      const expenseLines = page.getByTestId('dashboard-expense-lines')
        .getByTestId('dashboard-line');
      await expect(expenseLines).toHaveCount(2);
      await expect(expenseLines.nth(0)).toContainText('Groceries');
      await expectAmount(expenseLines.nth(0), 250);
      await expect(expenseLines.nth(1)).toContainText('Untagged expenses');
      await expectAmount(expenseLines.nth(1), 25);

      const untaggedNote = page.getByTestId('dashboard-untagged-note');
      await expect(untaggedNote).toContainText(
        '1 transaction is waiting for a tag',
      );
      await expect(untaggedNote.getByRole('link')).toHaveAttribute(
        'href',
        '/quick-tagging',
      );
      await expect(page.getByTestId('dashboard-empty-balance-sheet'))
        .toBeVisible();

      // Every transaction is this month's, so there is no baseline yet.
      const freshness = page.getByTestId('dashboard-freshness');
      await expect(freshness).toContainText(
        `Latest transaction ${localToday()}`,
      );
      await expect(freshness).toContainText('Typical figures appear');

      // The cash flow chart is drawn once Plot has loaded. The net worth chart
      // has no balances to draw.
      await expect(
        page.getByTestId('dashboard-cash-flow-chart').locator('svg').first(),
      ).toBeVisible();
      await page.screenshot({
        path: screenshotPath(testInfo, 'dashboard-this-month'),
        fullPage: true,
      });
    },
  );
});

test.describe('dashboard against earlier months', () => {
  test(
    'compares the month with earlier months and shows the history',
    async ({ page }, testInfo) => {
      const twoMonthsAgo = monthStart(2);
      const lastMonth = monthStart(1);
      const thisMonth = monthStart(0);

      // A house first valued two months ago, with the form's default current
      // term, so it counts towards working capital.
      await page.goto('/balance-sheet');
      await page.getByTestId('add-asset-button').click();
      const itemModal = page.getByTestId('balance-sheet-item-modal');
      await itemModal.getByTestId('item-name-input').fill('House');
      await itemModal.getByTestId('value-amount-input').fill('400000.00');
      await itemModal.getByTestId('value-as-of-input').fill(twoMonthsAgo.date);
      await itemModal.getByTestId('item-submit-button').click();
      await expect(itemModal).toBeHidden();

      await page.goto('/tagging');
      await page.getByTestId('create-first-tag-button').click();
      await submitTag(page, 'Salary', 'Income');
      await page.getByTestId('new-tag-button').click();
      await submitTag(page, 'Rent', 'Expense');

      // Pay and rent on the first of each month; rent went up this month.
      await page.goto('/transactions');
      for (
        const [month, rent] of [
          [twoMonthsAgo, '2000.00'],
          [lastMonth, '2000.00'],
          [thisMonth, '2500.00'],
        ] as const
      ) {
        await recordTransaction(page, {
          description: `Pay ${month.label}`,
          amount: '5000.00',
          credit: true,
          tag: 'Salary',
          date: month.date,
        });
        await recordTransaction(page, {
          description: `Rent ${month.label}`,
          amount: rent,
          tag: 'Rent',
          date: month.date,
        });
      }

      await page.getByRole('link', { name: 'Dashboard' }).click();

      // Position: runway is working capital over the average expenses.
      await expectAmount(page.getByTestId('dashboard-net-worth'), 400000);
      await expect(page.getByTestId('dashboard-runway')).toContainText(
        '200.0 months',
      );

      // Month: against the same days of the two earlier months.
      const month = page.getByTestId('dashboard-month');
      await expect(month).toContainText('the same days of the last 2 months');
      await expect(page.getByTestId('dashboard-freshness')).toContainText(
        `Latest transaction ${thisMonth.date}`,
      );
      await expectAmount(page.getByTestId('dashboard-expenses'), 2500);
      const expenses = page.getByTestId('dashboard-expenses');
      await expect(expenses.getByTestId('dashboard-typical')).toHaveText(
        '$2,000.00',
      );
      await expect(expenses.getByTestId('dashboard-change')).toHaveText(
        '+$500.00',
      );
      await expect(expenses.getByTestId('dashboard-change-percent')).toHaveText(
        '+25.0%',
      );
      await expect(
        page.getByTestId('dashboard-savings-rate').getByTestId(
          'dashboard-change',
        ),
      ).toHaveText('-10.0 pts');

      const rentLine = page.getByTestId('dashboard-expense-lines')
        .getByTestId('dashboard-line');
      await expect(rentLine).toHaveCount(1);
      await expect(rentLine).toContainText('Rent');
      await expect(rentLine.getByTestId('dashboard-change')).toHaveText(
        '+$500.00',
      );
      await expect(rentLine.getByTestId('dashboard-change-percent')).toHaveText(
        '+25.0%',
      );

      // History: two complete months and this month to date.
      const history = page.getByTestId('dashboard-history');
      await expect(history).toContainText(
        `Last 2 months and ${thisMonth.label} to date`,
      );
      await expectAmount(page.getByTestId('dashboard-total-expenses'), 4000);
      await expect(page.getByTestId('dashboard-total-expenses')).toContainText(
        '$2,000.00 a month',
      );
      await expect(
        page.getByTestId('dashboard-cash-flow').getByTestId(
          'dashboard-month-row',
        ),
      ).toHaveCount(3);
      await expect(
        page.getByTestId('dashboard-cash-flow-chart').locator('svg').first(),
      ).toBeVisible();
      await expect(
        page.getByTestId('dashboard-net-worth-chart').locator('svg').first(),
      ).toBeVisible();

      await page.screenshot({
        path: screenshotPath(testInfo, 'dashboard-with-history'),
        fullPage: true,
      });
    },
  );
});
