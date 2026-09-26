import { test, expect, type Page, type TestInfo } from '@playwright/test';

// The balance sheet page reads from both localStorage and the server. Each test
// gets a fresh browser context (so empty localStorage), and the dev-only reset
// endpoint clears the server's sheet and items, so every test starts from the
// "no sheet yet" state.
test.beforeEach(async ({ page }) => {
  const response = await page.request.delete('/api/test/balance-sheet');
  expect(response.status()).toBe(204);
});

const screenshotPath = (testInfo: TestInfo, name: string) =>
  testInfo.outputPath(
    `${name}${testInfo.retry > 0 ? `.retry-${testInfo.retry}` : ''}.png`,
  );

const modal = (page: Page) => page.getByTestId('balance-sheet-item-modal');

const deleteModal = (page: Page) =>
  page.getByTestId('delete-balance-sheet-item-modal');

const itemRow = (page: Page, name: string) =>
  page.locator('[data-testid^="balance-sheet-item-"]').filter({ hasText: name });

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
  await expect(page.getByTestId('no-balance-sheet-empty-state')).toBeVisible();
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
  const button = args.kind === 'asset' ? 'add-asset-button' : 'add-liability-button';
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
  test('tracks items, totals, and the empty state', async ({ page }, testInfo) => {
    await gotoNewBalanceSheet(page);

    // ── Create: one item per kind and term ───────────────────────────────────
    await addItem(page, { kind: 'asset', name: 'Chequing', balance: '2000.00' });
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
    await expect(itemGroup(page, 'Current assets')).toContainText('$2000.00');
    await expect(itemGroup(page, 'Non-current assets')).toContainText(
      '$400000.00',
    );
    await expect(itemGroup(page, 'Current liabilities')).toContainText(
      '$1500.00',
    );
    await expect(itemGroup(page, 'Non-current liabilities')).toContainText(
      '$300000.00',
    );

    // The server's totals are rendered as received, not recomputed by the page.
    await expect(summaryCard(page, 'total-assets')).toContainText('$402000.00');
    await expect(summaryCard(page, 'total-liabilities')).toContainText(
      '$301500.00',
    );
    await expect(summaryCard(page, 'net-worth')).toContainText('$100500.00');
    await expect(summaryCard(page, 'working-capital')).toContainText('$500.00');

    await page.screenshot({
      path: screenshotPath(testInfo, 'items-added'),
      fullPage: true,
    });

    // ── Update: a current asset moves every affected total ───────────────────
    await itemRow(page, 'Chequing').getByRole('button', { name: 'Edit' }).click();
    await expect(modal(page)).toBeVisible();
    await modal(page).getByTestId('item-balance-input').fill('3000.00');
    await modal(page).getByTestId('item-submit-button').click();
    await expect(modal(page)).toBeHidden();

    await expect(itemGroup(page, 'Current assets')).toContainText('$3000.00');
    await expect(summaryCard(page, 'total-assets')).toContainText('$403000.00');
    await expect(summaryCard(page, 'net-worth')).toContainText('$101500.00');
    await expect(summaryCard(page, 'working-capital')).toContainText('$1500.00');

    // ── Delete: a non-current item moves net worth but not working capital ───
    await deleteItem(page, 'House');

    await expect(summaryCard(page, 'net-worth')).toContainText('-$298500.00');
    await expect(summaryCard(page, 'working-capital')).toContainText('$1500.00');

    // ── Validation ───────────────────────────────────────────────────────────
    await page.getByTestId('add-asset-button').click();
    await expect(modal(page)).toBeVisible();
    await modal(page).getByTestId('item-submit-button').click();
    await expect(modal(page)).toContainText('Name cannot be empty');
    await modal(page).getByTestId('item-cancel-button').click();
    await expect(modal(page)).toBeHidden();

    // ── Delete everything: the sheet survives, so the empty-items state shows ─
    await deleteItem(page, 'Chequing');
    await deleteItem(page, 'Credit card');
    await deleteItem(page, 'Mortgage');

    await expect(page.getByTestId('no-items-empty-state')).toBeVisible();
    await expect(page.getByTestId('no-balance-sheet-empty-state')).toBeHidden();
    await expect(summaryCard(page, 'net-worth')).toContainText('$0.00');

    await page.screenshot({
      path: screenshotPath(testInfo, 'all-items-deleted'),
      fullPage: true,
    });
  });
});
