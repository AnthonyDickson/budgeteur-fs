import { type Page } from '@playwright/test';

import { test, expect } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

const tagModal = (page: Page) => page.getByTestId('tag-modal');
const deleteTagModal = (page: Page) => page.getByTestId('delete-tag-modal');

async function createFirstTag(page: Page, name: string) {
  await page.goto('/tagging');
  await page.getByTestId('create-first-tag-button').click();
  await tagModal(page).getByTestId('tag-name-input').fill(name);
  await tagModal(page).getByTestId('tag-submit-button').click();
  await expect(tagModal(page)).toBeHidden();
}

// The browser can close a dialog without the page asking (Escape, or a click
// outside it). The page must hear about it, or its model would still say the
// dialog is open and the next open would do nothing.
test.describe('dialogs', () => {
  test('a form dialog closed by the browser opens again', async ({ page }, testInfo) => {
    await page.goto('/tagging');

    await page.getByTestId('create-first-tag-button').click();
    await expect(tagModal(page)).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(tagModal(page)).toBeHidden();

    await page.getByTestId('create-first-tag-button').click();
    await expect(tagModal(page)).toBeVisible();
    // Outside the dialog, which sits in the middle of the page.
    await page.mouse.click(5, 5);
    await expect(tagModal(page)).toBeHidden();

    await page.getByTestId('create-first-tag-button').click();
    await expect(tagModal(page).getByTestId('tag-name-input')).toBeVisible();
    await page.screenshot({
      path: screenshotPath(testInfo, 'form-dialog-reopened'),
      fullPage: true,
    });
  });

  test('a delete dialog closed by the browser opens again', async ({ page }, testInfo) => {
    await createFirstTag(page, 'Groceries');
    const deleteButton = page.getByRole('button', { name: 'Delete tag Groceries' });

    await deleteButton.click();
    await expect(deleteTagModal(page)).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(deleteTagModal(page)).toBeHidden();

    await deleteButton.click();
    await expect(deleteTagModal(page)).toBeVisible();
    await expect(deleteTagModal(page)).toContainText('Groceries');
    await page.screenshot({
      path: screenshotPath(testInfo, 'delete-dialog-reopened'),
      fullPage: true,
    });
  });
});
