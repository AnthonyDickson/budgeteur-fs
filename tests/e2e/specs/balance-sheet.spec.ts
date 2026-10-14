import { type Locator, type Page } from '@playwright/test';

import { expectAmount } from '../support/amount';
import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

const modal = (page: Page) => page.getByTestId('balance-sheet-item-modal');
const valueModal = (page: Page) => page.getByTestId('value-modal');

const deleteModal = (page: Page) =>
  page.getByTestId('delete-balance-sheet-item-modal');

const itemRow = (page: Page, name: string) =>
  page.locator('[data-testid^="balance-sheet-item-"]').filter({
    hasText: name,
  });

/// Open a line's details page by clicking its row.
async function openDetails(page: Page, row: Locator) {
  await row.getByTestId(/^open-(item|account)-/).click();
  await expect(page.getByTestId('line-details-page')).toBeVisible();
}

/// Return from a details page to the balance sheet.
async function backToSheet(page: Page) {
  await page.getByTestId('line-details-back').click();
  await expect(page.getByTestId('balance-sheet-page')).toBeVisible();
}

/// Open an item's value form from its details page.
async function openItem(page: Page, name: string) {
  await openDetails(page, itemRow(page, name));
  await page.getByTestId('record-observation-button').click();
  await expect(valueModal(page)).toBeVisible();
}

/// Open an item's edit dialog from its details page.
async function editItem(page: Page, name: string) {
  await openDetails(page, itemRow(page, name));
  await page.getByTestId('edit-line-button').click();
  await expect(modal(page)).toBeVisible();
}

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

/// Add an item through the modal. The side is chosen by which header button
/// opens the form; the term defaults to the current one.
async function addItem(
  page: Page,
  args: {
    side: 'asset' | 'liability';
    name: string;
    value: string;
    nonCurrent?: boolean;
  },
) {
  const button = args.side === 'asset'
    ? 'add-asset-button'
    : 'add-liability-button';
  await page.getByTestId(button).click();
  await expect(modal(page)).toBeVisible();
  await modal(page).getByTestId('item-name-input').fill(args.name);
  await modal(page).getByTestId('value-amount-input').fill(args.value);
  if (args.nonCurrent) {
    await modal(page).getByTestId('item-term-NonCurrent').check();
  }
  await modal(page).getByTestId('item-submit-button').click();
  await expect(modal(page)).toBeHidden();
  await expect(itemRow(page, args.name)).toBeVisible();
}

async function deleteItem(page: Page, name: string) {
  await editItem(page, name);
  await modal(page).getByTestId('item-delete-button').click();
  await expect(modal(page)).toBeHidden();
  await expect(deleteModal(page)).toBeVisible();
  await deleteModal(page)
    .getByTestId('balance-sheet-item-delete-confirm-button')
    .click();
  await expect(deleteModal(page)).toBeHidden();
  // Deleting the line returns to the balance sheet.
  await expect(page.getByTestId('balance-sheet-page')).toBeVisible();
  await expect(itemRow(page, name)).toHaveCount(0);
}

test.describe('balance sheet', () => {
  test(
    'tracks items, totals, and the empty state',
    async ({ page }, testInfo) => {
      await gotoNewBalanceSheet(page);

      // ── Create: one item per side and term ───────────────────────────────────
      await addItem(page, {
        side: 'asset',
        name: 'Chequing',
        value: '2000.00',
      });
      await addItem(page, {
        side: 'asset',
        name: 'House',
        value: '400000.00',
        nonCurrent: true,
      });
      await addItem(page, {
        side: 'liability',
        name: 'Credit card',
        value: '1500.00',
      });
      await addItem(page, {
        side: 'liability',
        name: 'Mortgage',
        value: '300000.00',
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

      // ── Record a value: a current asset moves every affected total ──────────
      await openItem(page, 'Chequing');
      await valueModal(page).getByTestId('value-amount-input').fill('3000.00');
      await valueModal(page).getByTestId('value-submit-button').click();
      await expect(valueModal(page)).toBeHidden();
      await backToSheet(page);

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

test.describe('closing items', () => {
  test('a closed item leaves the sheet and can be reopened', async ({ page }) => {
    await gotoNewBalanceSheet(page);
    await addItem(page, {
      side: 'asset',
      name: 'House',
      value: '400000.00',
      nonCurrent: true,
    });
    await expectAmount(summaryCard(page, 'net-worth'), 400000);

    // Sold: it is closed from its details page.
    await openDetails(page, itemRow(page, 'House'));
    await page.getByTestId('close-line-button').click();
    const closeModal = page.getByTestId('close-modal');
    await closeModal.getByTestId('close-date-input').fill('2026-01-15');
    await closeModal.getByTestId('close-submit-button').click();
    await expect(closeModal).toBeHidden();
    await expect(page.getByTestId('line-details-closed-on')).toContainText(
      '2026-01-15',
    );

    // It leaves the sheet and its totals.
    await page.getByTestId('line-details-back').click();
    await expect(itemRow(page, 'House')).toHaveCount(0);
    await expectAmount(summaryCard(page, 'net-worth'), 0);

    // It is listed, collapsed, with its close date.
    const closed = page.getByTestId('closed-lines');
    await expect(closed).toContainText('Closed (1)');
    await closed.locator('summary').click();
    await expect(closed).toContainText('Closed on 2026-01-15');

    // Reopened from its details page, it is back on the sheet.
    await closed.getByTestId(/^open-closed-item-/).click();
    await page.getByTestId('reopen-line-button').click();
    await expect(page.getByTestId('line-details-closed-on')).toHaveCount(0);
    await page.getByTestId('line-details-back').click();

    await expect(itemRow(page, 'House')).toBeVisible();
    await expectAmount(summaryCard(page, 'net-worth'), 400000);
    await expect(closed).toHaveCount(0);
  });
});

test.describe('line details', () => {
  test("an item's history records and deletes values", async ({ page }) => {
    await gotoNewBalanceSheet(page);
    await addItem(page, {
      side: 'asset',
      name: 'House',
      value: '400000.00',
      nonCurrent: true,
    });

    // The line opens its details page, with the first value.
    await openDetails(page, itemRow(page, 'House'));
    const rows = page.locator('[data-testid^="observation-2"]');
    await expect(rows).toHaveCount(1);

    // An older value is recorded: it is listed below the current one.
    await page.getByTestId('record-observation-button').click();
    await expect(valueModal(page)).toBeVisible();
    await valueModal(page).getByTestId('value-amount-input').fill('380000.00');
    await valueModal(page).getByTestId('value-as-of-input').fill('2026-01-01');
    await valueModal(page).getByTestId('value-submit-button').click();
    await expect(valueModal(page)).toBeHidden();

    await expect(rows).toHaveCount(2);
    await expectAmount(rows.first(), 400000);
    await expectAmount(page.getByTestId('observation-2026-01-01'), 380000);

    // The newer value is deleted: the older one becomes current.
    await rows.first().getByTestId(/^delete-observation-/).click();
    const deleteDialog = page.getByTestId('delete-observation-modal');
    await expect(deleteDialog).toBeVisible();
    await deleteDialog.getByTestId('delete-observation-confirm-button').click();
    await expect(deleteDialog).toBeHidden();
    await expect(rows).toHaveCount(1);
    await expect(page.getByTestId('line-details-current')).toContainText(
      '2026-01-01',
    );

    // The only value left cannot be deleted: an item always has a value.
    await expect(
      rows.first().getByTestId(/^delete-observation-/),
    ).toBeDisabled();

    // Back on the balance sheet, the line shows the older value.
    await page.getByTestId('line-details-back').click();
    await expect(itemRow(page, 'House')).toBeVisible();
    await expectAmount(itemRow(page, 'House'), 380000);
  });
});

const accountModal = (page: Page) => page.getByTestId('account-modal');
const balanceModal = (page: Page) => page.getByTestId('balance-modal');

const accountRow = (page: Page, name: string) =>
  page.locator('[data-testid^="balance-sheet-account-"]').filter({
    hasText: name,
  });

/// Open an account's balance form from its details page.
async function openAccount(page: Page, row: Locator) {
  await openDetails(page, row);
  await page.getByTestId('record-observation-button').click();
  await expect(balanceModal(page)).toBeVisible();
}

/// Open an account's edit dialog from its details page.
async function editAccount(page: Page, name: string) {
  await openDetails(page, accountRow(page, name));
  await page.getByTestId('edit-line-button').click();
  await expect(accountModal(page)).toBeVisible();
}

/// Fill the balance fields of the open account or balance modal.
async function fillBalance(
  dialog: Locator,
  args: { side: 'Asset' | 'Liability'; amount: string },
) {
  await dialog.getByTestId(`balance-side-${args.side}`).check();
  await dialog.getByTestId('balance-amount-input').fill(args.amount);
}

/// Record a balance through the open balance modal.
async function recordBalance(
  page: Page,
  args: { side: 'Asset' | 'Liability'; amount: string },
) {
  await expect(balanceModal(page)).toBeVisible();
  await fillBalance(balanceModal(page), args);
  await balanceModal(page).getByTestId('balance-submit-button').click();
  await expect(balanceModal(page)).toBeHidden();
}

test.describe('balance sheet accounts', () => {
  test(
    'places accounts by the sign of their balance',
    async ({ page }, testInfo) => {
      await gotoNewBalanceSheet(page);

      // An account with an asset balance is a current asset.
      await page.getByTestId('add-account-button').click();
      await expect(accountModal(page)).toBeVisible();
      await accountModal(page).getByTestId('account-name-input').fill(
        'Everyday',
      );
      await accountModal(page).getByTestId('account-number-input').fill(
        '12-3456-0789012-00',
      );
      await fillBalance(accountModal(page), {
        side: 'Asset',
        amount: '1000.00',
      });
      await accountModal(page).getByTestId('account-submit-button').click();
      await expect(accountModal(page)).toBeHidden();
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

      // A liability balance makes it a current liability.
      await openAccount(page, unknown);
      await recordBalance(page, { side: 'Liability', amount: '400.00' });
      await backToSheet(page);
      await expect(unknown).toBeHidden();
      await expectAmount(itemGroup(page, 'Current liabilities'), 400);
      await expectAmount(summaryCard(page, 'net-worth'), 600);
      await expectAmount(summaryCard(page, 'working-capital'), 600);

      await page.screenshot({
        path: screenshotPath(testInfo, 'accounts-added'),
        fullPage: true,
      });

      // Deleting an account warns that its transactions go with it.
      await editAccount(page, 'Everyday');
      await accountModal(page).getByTestId('account-delete-button').click();
      await expect(accountModal(page)).toBeHidden();
      const deleteAccount = page.getByTestId('delete-account-modal');
      await expect(deleteAccount).toContainText('transactions');
      await deleteAccount.getByTestId('account-delete-confirm-button').click();
      await expect(deleteAccount).toBeHidden();
      await expect(page.getByTestId('balance-sheet-page')).toBeVisible();
      await expect(accountRow(page, 'Everyday')).toHaveCount(0);
      await expectAmount(summaryCard(page, 'net-worth'), -400);
    },
  );

  test(
    'an overdrawn account moves sides, and editing it keeps its balance',
    async ({ page }) => {
      await gotoNewBalanceSheet(page);

      await page.getByTestId('add-account-button').click();
      await accountModal(page).getByTestId('account-name-input').fill(
        'Everyday',
      );
      await fillBalance(accountModal(page), {
        side: 'Asset',
        amount: '1000.00',
      });
      await accountModal(page).getByTestId('account-submit-button').click();
      await expect(accountModal(page)).toBeHidden();
      await expectAmount(itemGroup(page, 'Current assets'), 1000);

      // The balance form opens on the current balance.
      await openAccount(page, accountRow(page, 'Everyday'));
      await expect(balanceModal(page).getByTestId('balance-amount-input'))
        .toHaveValue('1000.00');

      // Recording an overdrawn balance moves the line to the liabilities.
      await recordBalance(page, { side: 'Liability', amount: '50.00' });
      await backToSheet(page);
      await expectAmount(itemGroup(page, 'Current assets'), 0);
      await expectAmount(itemGroup(page, 'Current liabilities'), 50);
      await expectAmount(summaryCard(page, 'net-worth'), -50);

      // Editing the details changes the name and leaves the balance.
      await editAccount(page, 'Everyday');
      await expect(accountModal(page).getByTestId('balance-amount-input'))
        .toHaveCount(0);
      await accountModal(page).getByTestId('account-name-input').fill('Bills');
      await accountModal(page).getByTestId('account-submit-button').click();
      await expect(accountModal(page)).toBeHidden();
      await backToSheet(page);
      await expect(accountRow(page, 'Bills')).toBeVisible();
      await expectAmount(itemGroup(page, 'Current liabilities'), 50);
    },
  );
});
