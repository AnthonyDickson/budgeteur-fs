import { type Page } from '@playwright/test';

import { expect, test } from '../support/fixtures';
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
  test(
    'a form dialog closed by the browser opens again',
    async ({ page }, testInfo) => {
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
    },
  );

  // Help opens as a popover above the dialog. Escape and outside clicks close
  // the help first and leave the dialog open.
  test(
    'help in a dialog closes before the dialog',
    async ({ page }, testInfo) => {
      await page.goto('/tagging');
      await page.getByTestId('create-first-tag-button').click();
      const help = page.getByTestId('tag-name-help');

      await tagModal(page).getByTestId('tag-name-help-button').click();
      await expect(help).toBeVisible();
      await expect(help).toContainText('Prefer broad categories');
      await page.screenshot({
        path: screenshotPath(testInfo, 'dialog-help-open'),
        fullPage: true,
      });
      await page.keyboard.press('Escape');
      await expect(help).toBeHidden();
      await expect(tagModal(page)).toBeVisible();

      await tagModal(page).getByTestId('tag-name-help-button').click();
      await expect(help).toBeVisible();
      await tagModal(page).getByRole('heading').click();
      await expect(help).toBeHidden();
      await expect(tagModal(page)).toBeVisible();
    },
  );

  test(
    'a delete dialog closed by the browser opens again',
    async ({ page }, testInfo) => {
      await createFirstTag(page, 'Groceries');
      const openDelete = async () => {
        await page.getByRole('button', { name: 'Edit tag Groceries' }).click();
        await tagModal(page).getByTestId('tag-delete-button').click();
      };

      await openDelete();
      await expect(deleteTagModal(page)).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(deleteTagModal(page)).toBeHidden();

      await openDelete();
      await expect(deleteTagModal(page)).toBeVisible();
      await expect(deleteTagModal(page)).toContainText('Groceries');
      await page.screenshot({
        path: screenshotPath(testInfo, 'delete-dialog-reopened'),
        fullPage: true,
      });
    },
  );
});
