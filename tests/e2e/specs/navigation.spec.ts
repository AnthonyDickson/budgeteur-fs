import { type Page } from '@playwright/test';

import { test, expect } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

/// Open the transaction modal from the transactions page.
async function openTransactionModal(page: Page) {
  await page.getByTestId('record-transaction-button').click();
  await expect(page.getByTestId('transaction-modal')).toBeVisible();
}

/// The tagging page is shown with no dialog left open from the previous page,
/// and its own tag modal opens with its form.
async function expectUsableTaggingPage(page: Page) {
  await expect(page).toHaveURL(/\/tagging$/);
  await expect(page.getByTestId('no-tags-empty-state')).toBeVisible();
  await expect(page.locator('dialog[open]')).toHaveCount(0);

  await page.getByTestId('create-first-tag-button').click();
  await expect(page.getByTestId('tag-modal').getByTestId('tag-name-input')).toBeVisible();
}

test.describe('navigation', () => {
  test('the no-tags link in the transaction modal opens the tagging page', async ({
    page,
  }, testInfo) => {
    await page.goto('/transactions');
    await openTransactionModal(page);

    await page
      .getByTestId('transaction-modal')
      .getByRole('link', { name: 'Create one on the Tagging page' })
      .click();

    await expect(page).toHaveURL(/\/tagging$/);
    await page.screenshot({
      path: screenshotPath(testInfo, 'tagging-page-after-link'),
      fullPage: true,
    });
    await expectUsableTaggingPage(page);
  });

  test('going back with the transaction modal open leaves no dialog open', async ({
    page,
  }, testInfo) => {
    await page.goto('/tagging');
    await page.getByRole('link', { name: 'Transactions' }).click();
    await expect(page).toHaveURL(/\/transactions$/);
    await openTransactionModal(page);

    await page.goBack();

    await expect(page).toHaveURL(/\/tagging$/);
    await page.screenshot({
      path: screenshotPath(testInfo, 'tagging-page-after-back'),
      fullPage: true,
    });
    await expectUsableTaggingPage(page);
  });
});
