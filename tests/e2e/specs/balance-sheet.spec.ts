import { type Page } from '@playwright/test';

import { expectAmount } from '../support/amount';
import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

const modal = (page: Page) => page.getByTestId('balance-sheet-item-modal');

const deleteModal = (page: Page) =>
  page.getByTestId('delete-balance-sheet-item-modal');

const itemRow = (page: Page, name: string) =>
  page.locator('[data-testid^="balance-sheet-item-"]').filter({
    hasText: name,
  });

/// The header row holding one term's subtotal, e.g. "Current assets $2000.00".
/// The name must match exactly, or "Current assets" would also match
/// "Non-current assets".
const itemGroup = (page: Page, title: string) =>
  page
    .locator('div')
    .filter({
      has: page.getByRole('heading', { level: 3, name: title, exact: true }),
    })
    .last();

const summaryCard = (page: Page, testId: string) => page.getByTestId(testId);

async function gotoNewBalanceSheet(page: Page) {
  await page.goto('/balance-sheet');
  await expect(page.getByTestId('no-items-empty-state')).toBeVisible();
}

/// Add an item through the modal. The kind is chosen by which header button
/// opens the form; the term defaults to the current one.
async function addItem(
  page: Page,
  args: {
    kind: 'asset' | 'liability';
    name: string;
    balance: string;
    nonCurrent?: boolean;
  },
) {
  const button = args.kind === 'asset'
    ? 'add-asset-button'
    : 'add-liability-button';
  await page.getByTestId(button).click();
  await expect(modal(page)).toBeVisible();
  await modal(page).getByTestId('item-name-input').fill(args.name);
  await modal(page).getByTestId('item-balance-input').fill(args.balance);
  if (args.nonCurrent) {
    await modal(page).getByTestId('item-term-NonCurrent').check();
  }
  await modal(page).getByTestId('item-submit-button').click();
  await expect(modal(page)).toBeHidden();
  await expect(itemRow(page, args.name)).toBeVisible();
}

async function deleteItem(page: Page, name: string) {
  await itemRow(page, name).getByRole('button', { name: 'Delete' }).click();
  await expect(deleteModal(page)).toBeVisible();
  await deleteModal(page)
    .getByTestId('balance-sheet-item-delete-confirm-button')
    .click();
  await expect(deleteModal(page)).toBeHidden();
  await expect(itemRow(page, name)).toHaveCount(0);
}

test.describe('balance sheet', () => {
  test(
    'tracks items, totals, and the empty state',
    async ({ page }, testInfo) => {
      await gotoNewBalanceSheet(page);

      // ── Create: one item per kind and term ───────────────────────────────────
      await addItem(page, {
        kind: 'asset',
        name: 'Chequing',
        balance: '2000.00',
      });
      await addItem(page, {
        kind: 'asset',
        name: 'House',
        balance: '400000.00',
        nonCurrent: true,
      });
      await addItem(page, {
        kind: 'liability',
        name: 'Credit card',
        balance: '1500.00',
      });
      await addItem(page, {
        kind: 'liability',
        name: 'Mortgage',
        balance: '300000.00',
        nonCurrent: true,
      });

      await expect(page.getByTestId('no-items-empty-state')).toBeHidden();

      // Every item is filed under its term, with the term's subtotal.
      await expectAmount(itemGroup(page, 'Current assets'), 2000);
      await expectAmount(itemGroup(page, 'Non-current assets'), 400000);
      await expectAmount(itemGroup(page, 'Current liabilities'), 1500);
      await expectAmount(itemGroup(page, 'Non-current liabilities'), 300000);

      // The server's totals are rendered as received, not recomputed by the page.
      await expectAmount(summaryCard(page, 'total-assets'), 402000);
      await expectAmount(summaryCard(page, 'total-liabilities'), 301500);
      await expectAmount(summaryCard(page, 'net-worth'), 100500);
      await expectAmount(summaryCard(page, 'working-capital'), 500);

      await page.screenshot({
        path: screenshotPath(testInfo, 'items-added'),
        fullPage: true,
      });

      // ── Update: a current asset moves every affected total ───────────────────
      await itemRow(page, 'Chequing').getByRole('button', { name: 'Edit' })
        .click();
      await expect(modal(page)).toBeVisible();
      await modal(page).getByTestId('item-balance-input').fill('3000.00');
      await modal(page).getByTestId('item-submit-button').click();
      await expect(modal(page)).toBeHidden();

      await expectAmount(itemGroup(page, 'Current assets'), 3000);
      await expectAmount(summaryCard(page, 'total-assets'), 403000);
      await expectAmount(summaryCard(page, 'net-worth'), 101500);
      await expectAmount(summaryCard(page, 'working-capital'), 1500);

      // ── Delete: a non-current item moves net worth but not working capital ───
      await deleteItem(page, 'House');

      await expectAmount(summaryCard(page, 'net-worth'), -298500);
      await expectAmount(summaryCard(page, 'working-capital'), 1500);

      // ── Validation ───────────────────────────────────────────────────────────
      await page.getByTestId('add-asset-button').click();
      await expect(modal(page)).toBeVisible();
      await modal(page).getByTestId('item-submit-button').click();
      await expect(modal(page)).toContainText('Name cannot be empty');
      await modal(page).getByTestId('item-cancel-button').click();
      await expect(modal(page)).toBeHidden();

      // ── Delete everything: the empty state shows ─────────────────────────────
      await deleteItem(page, 'Chequing');
      await deleteItem(page, 'Credit card');
      await deleteItem(page, 'Mortgage');

      await expect(page.getByTestId('no-items-empty-state')).toBeVisible();
      await expectAmount(summaryCard(page, 'net-worth'), 0);

      await page.screenshot({
        path: screenshotPath(testInfo, 'all-items-deleted'),
        fullPage: true,
      });
    },
  );
});

const accountModal = (page: Page) => page.getByTestId('account-modal');

const accountRow = (page: Page, name: string) =>
  page.locator('[data-testid^="balance-sheet-account-"]').filter({
    hasText: name,
  });

/// Fill the open account modal's balance as held or owed, and save.
async function saveBalance(
  page: Page,
  args: { side: 'Held' | 'Owed'; balance: string },
) {
  await accountModal(page).getByTestId(`account-side-${args.side}`).check();
  await accountModal(page).getByTestId('account-balance-input').fill(
    args.balance,
  );
  await accountModal(page).getByTestId('account-submit-button').click();
  await expect(accountModal(page)).toBeHidden();
}

test.describe('balance sheet accounts', () => {
  test(
    'places accounts by the sign of their balance',
    async ({ page }, testInfo) => {
      await gotoNewBalanceSheet(page);

      // An account with a held balance is a current asset.
      await page.getByTestId('add-account-button').click();
      await expect(accountModal(page)).toBeVisible();
      await accountModal(page).getByTestId('account-name-input').fill(
        'Everyday',
      );
      await accountModal(page).getByTestId('account-number-input').fill(
        '12-3456-0789012-00',
      );
      await saveBalance(page, { side: 'Held', balance: '1000.00' });
      await expect(accountRow(page, 'Everyday')).toContainText(
        '12-3456-0789012-000',
      );
      await expectAmount(itemGroup(page, 'Current assets'), 1000);

      // An account without a balance is listed apart and left out of the totals.
      await page.getByTestId('add-account-button').click();
      await accountModal(page).getByTestId('account-name-input').fill(
        'Credit card',
      );
      await accountModal(page).getByTestId('account-submit-button').click();
      await expect(accountModal(page)).toBeHidden();
      const unknown = page.getByTestId('unknown-balances');
      await expect(unknown).toContainText('Credit card');
      await expectAmount(summaryCard(page, 'net-worth'), 1000);

      // An owed balance makes it a current liability.
      await unknown.getByRole('button', { name: 'Enter balance' }).click();
      await expect(accountModal(page)).toBeVisible();
      await saveBalance(page, { side: 'Owed', balance: '400.00' });
      await expect(unknown).toBeHidden();
      await expectAmount(itemGroup(page, 'Current liabilities'), 400);
      await expectAmount(summaryCard(page, 'net-worth'), 600);
      await expectAmount(summaryCard(page, 'working-capital'), 600);

      await page.screenshot({
        path: screenshotPath(testInfo, 'accounts-added'),
        fullPage: true,
      });

      // Deleting an account warns that its transactions go with it.
      await accountRow(page, 'Everyday').getByRole('button', { name: 'Delete' })
        .click();
      const deleteAccount = page.getByTestId('delete-account-modal');
      await expect(deleteAccount).toContainText('transactions');
      await deleteAccount.getByTestId('account-delete-confirm-button').click();
      await expect(deleteAccount).toBeHidden();
      await expect(accountRow(page, 'Everyday')).toHaveCount(0);
      await expectAmount(summaryCard(page, 'net-worth'), -400);
    },
  );
});
