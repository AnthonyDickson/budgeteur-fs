import { type Page } from '@playwright/test';

import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

const colorTestId = (hex: string) => `tag-color-hex${hex.replace('#', '')}`;

const tagModal = (page: Page) => page.getByTestId('tag-modal');
const ruleModal = (page: Page) => page.getByTestId('rule-modal');

const tagRow = (page: Page, name: string) =>
  page.locator('[data-testid^="tag-row-"]').filter({ hasText: name });

const ruleRow = (page: Page, pattern: string) =>
  page.locator('[data-testid="rule-row"]', {
    has: page.locator('code', { hasText: pattern }),
  });

const toast = (page: Page, text: string) =>
  page.getByTestId('toast').filter({ hasText: text });

/// Navigate to the tagging page and wait for the empty state. Each test starts
/// with no data (see support/fixtures.ts), so this is deterministic.
async function gotoEmptyTagging(page: Page) {
  await page.goto('/tagging');
  await expect(page.getByTestId('no-tags-empty-state')).toBeVisible();
}

/// Fill in and submit the currently open tag modal (does not wait for the
/// response).
async function submitTagForm(page: Page, name: string, color?: string) {
  const modal = tagModal(page);
  await expect(modal).toBeVisible();
  await modal.getByTestId('tag-name-input').fill(name);
  if (color) {
    await modal.getByTestId(colorTestId(color)).click();
  }
  await modal.getByTestId('tag-submit-button').click();
}

/// Create the very first tag from the empty state.
async function createFirstTag(page: Page, name: string, color?: string) {
  await page.getByTestId('create-first-tag-button').click();
  await submitTagForm(page, name, color);
  await expect(tagModal(page)).toBeHidden();
  await expect(tagRow(page, name)).toBeVisible();
}

/// Create another tag once the page already has at least one.
async function createTag(page: Page, name: string, color?: string) {
  await page.getByTestId('new-tag-button').click();
  await submitTagForm(page, name, color);
  await expect(tagModal(page)).toBeHidden();
  await expect(tagRow(page, name)).toBeVisible();
}

/// Create a rule for the currently selected tag.
async function createRule(page: Page, pattern: string) {
  await page.getByTestId('new-rule-button').click();
  const modal = ruleModal(page);
  await expect(modal).toBeVisible();
  await modal.getByTestId('rule-pattern-input').fill(pattern);
  await modal.getByTestId('rule-submit-button').click();
  await expect(modal).toBeHidden();
  await expect(ruleRow(page, pattern)).toBeVisible();
}

/// Record an untagged transaction from the transactions page.
async function recordTransaction(page: Page, description: string) {
  await page.goto('/transactions');
  await page.getByTestId('record-transaction-button').click();
  const modal = page.getByTestId('transaction-modal');
  await expect(modal).toBeVisible();
  await modal.getByTestId('transaction-amount-input').fill('10.00');
  await modal.getByTestId('transaction-description-input').fill(description);
  await modal.getByTestId('transaction-date-input').fill('2026-10-01');
  await modal.getByTestId('transaction-submit-button').click();
  await expect(modal).toBeHidden();
}

test.describe('tagging', () => {
  test(
    'creates the first tag from the empty state',
    async ({ page }, testInfo) => {
      await gotoEmptyTagging(page);

      await createFirstTag(page, 'Groceries', '#EF4444');

      await expect(page.getByTestId('no-tags-empty-state')).toBeHidden();
      await expect(page.getByTestId('tags-panel')).toBeVisible();

      // The newly created tag is selected and owns the rules panel.
      await expect(tagRow(page, 'Groceries')).toHaveAttribute(
        'aria-current',
        'true',
      );
      await expect(page.getByTestId('rules-panel')).toContainText('Groceries');
      await expect(toast(page, "Created tag 'Groceries'")).toBeVisible();

      await page.screenshot({
        path: screenshotPath(testInfo, 'first-tag-created'),
        fullPage: true,
      });
    },
  );

  test('manages a full tag and rule lifecycle', async ({ page }, testInfo) => {
    await gotoEmptyTagging(page);

    await createFirstTag(page, 'Groceries');
    await createTag(page, 'Transport');
    // The most recently created tag becomes selected.
    await expect(page.getByTestId('rules-panel')).toContainText('Transport');

    await createRule(page, 'STARBUCKS');
    await expect(toast(page, 'Created rule STARBUCKS')).toBeVisible();

    // Edit the rule's pattern.
    await ruleRow(page, 'STARBUCKS').getByRole('button', { name: 'Edit' })
      .click();
    await expect(ruleModal(page)).toBeVisible();
    await ruleModal(page).getByTestId('rule-pattern-input').fill('LATTE');
    await ruleModal(page).getByTestId('rule-submit-button').click();
    await expect(ruleModal(page)).toBeHidden();
    await expect(ruleRow(page, 'LATTE')).toBeVisible();
    await expect(toast(page, 'Updated rule LATTE')).toBeVisible();

    // Selecting another tag swaps the rules panel to that tag's rules.
    await tagRow(page, 'Groceries').click();
    await expect(page.getByTestId('rules-panel')).toContainText('Groceries');
    await expect(page.getByTestId('rules-panel')).toContainText(
      'No rules for "Groceries" yet',
    );

    // Delete the rule.
    await tagRow(page, 'Transport').click();
    await ruleRow(page, 'LATTE').getByRole('button', { name: 'Delete' })
      .click();
    const deleteRuleModal = page.getByTestId('delete-rule-modal');
    await expect(deleteRuleModal).toBeVisible();
    await deleteRuleModal.getByTestId('rule-delete-confirm-button').click();
    await expect(deleteRuleModal).toBeHidden();
    await expect(ruleRow(page, 'LATTE')).toHaveCount(0);
    await expect(toast(page, 'Deleted rule LATTE')).toBeVisible();

    // Edit the tag.
    await page.getByRole('button', { name: 'Edit tag Transport' }).click();
    await expect(tagModal(page)).toBeVisible();
    await tagModal(page).getByTestId('tag-name-input').fill('Travel');
    await tagModal(page).getByTestId('tag-submit-button').click();
    await expect(tagModal(page)).toBeHidden();
    await expect(tagRow(page, 'Travel')).toBeVisible();
    await expect(page.getByTestId('rules-panel')).toContainText('Travel');
    await expect(toast(page, "Updated tag 'Travel'")).toBeVisible();

    // Delete the tag; selection moves to the remaining one.
    await page.getByRole('button', { name: 'Delete tag Travel' }).click();
    const deleteTagModal = page.getByTestId('delete-tag-modal');
    await expect(deleteTagModal).toBeVisible();
    await deleteTagModal.getByTestId('tag-delete-confirm-button').click();
    await expect(deleteTagModal).toBeHidden();
    await expect(tagRow(page, 'Travel')).toHaveCount(0);
    await expect(tagRow(page, 'Groceries')).toHaveAttribute(
      'aria-current',
      'true',
    );
    await expect(toast(page, 'Deleted tag Travel')).toBeVisible();

    await page.screenshot({
      path: screenshotPath(testInfo, 'lifecycle-complete'),
      fullPage: true,
    });
  });

  test('validates tag names', async ({ page }, testInfo) => {
    await gotoEmptyTagging(page);
    await page.getByTestId('create-first-tag-button').click();
    const modal = tagModal(page);

    // A blank name is rejected on submit.
    await modal.getByTestId('tag-submit-button').click();
    await expect(modal).toContainText('Name cannot be empty');
    await page.screenshot({
      path: screenshotPath(testInfo, 'tag-name-required'),
      fullPage: true,
    });

    // Over-long names are rejected as you type.
    await modal.getByTestId('tag-name-input').fill('x'.repeat(65));
    await expect(modal).toContainText(
      'Name cannot be longer than 64 characters',
    );
    await page.screenshot({
      path: screenshotPath(testInfo, 'tag-name-too-long'),
      fullPage: true,
    });

    // A valid name saves.
    await modal.getByTestId('tag-name-input').fill('Groceries');
    await modal.getByTestId('tag-submit-button').click();
    await expect(modal).toBeHidden();

    // Reusing an existing name is rejected before the round trip.
    await page.getByTestId('new-tag-button').click();
    await expect(modal).toBeVisible();
    await modal.getByTestId('tag-name-input').fill('Groceries');
    await modal.getByTestId('tag-submit-button').click();
    await expect(modal).toContainText('A tag with this name already exists');
    await page.screenshot({
      path: screenshotPath(testInfo, 'tag-name-duplicate'),
      fullPage: true,
    });
    await modal.getByTestId('tag-cancel-button').click();
    await expect(modal).toBeHidden();
  });

  test('deletes a tag and cascades its rules', async ({ page }) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'STARBUCKS');
    await createRule(page, 'COUNTDOWN');

    await page.getByRole('button', { name: 'Delete tag Groceries' }).click();
    const modal = page.getByTestId('delete-tag-modal');
    await expect(modal).toBeVisible();
    await expect(modal).toContainText('Its 2 matching rules are deleted too');

    // Cancel keeps the tag.
    await modal.getByTestId('tag-delete-cancel-button').click();
    await expect(modal).toBeHidden();
    await expect(tagRow(page, 'Groceries')).toBeVisible();

    // Confirming removes the tag (and its rules, back to the empty state).
    await page.getByRole('button', { name: 'Delete tag Groceries' }).click();
    await expect(modal).toBeVisible();
    await modal.getByTestId('tag-delete-confirm-button').click();
    await expect(modal).toBeHidden();
    await expect(page.getByTestId('no-tags-empty-state')).toBeVisible();
    await expect(toast(page, 'Deleted tag Groceries')).toBeVisible();
  });

  test('validates rule patterns', async ({ page }, testInfo) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');

    await page.getByTestId('new-rule-button').click();
    const modal = ruleModal(page);
    await expect(modal).toBeVisible();
    await modal.getByTestId('rule-submit-button').click();
    await expect(modal).toContainText('Pattern cannot be empty');
    await page.screenshot({
      path: screenshotPath(testInfo, 'rule-pattern-required'),
      fullPage: true,
    });
    await modal.getByTestId('rule-cancel-button').click();
    await expect(modal).toBeHidden();
  });

  test('rule patterns are unique per user, ignoring case', async ({ page }) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'STARBUCKS');

    // The same pattern in another case is rejected under the same tag.
    await page.getByTestId('new-rule-button').click();
    const modal = ruleModal(page);
    await expect(modal).toBeVisible();
    await modal.getByTestId('rule-pattern-input').fill('starbucks');
    await modal.getByTestId('rule-submit-button').click();
    await expect(modal).toContainText(
      'A rule with this pattern already exists',
    );
    await modal.getByTestId('rule-cancel-button').click();
    await expect(modal).toBeHidden();

    // And under a different tag.
    await createTag(page, 'Transport');
    await page.getByTestId('new-rule-button').click();
    await expect(modal).toBeVisible();
    await modal.getByTestId('rule-pattern-input').fill('STARBUCKS');
    await modal.getByTestId('rule-submit-button').click();
    await expect(modal).toContainText(
      'A rule with this pattern already exists',
    );
    await modal.getByTestId('rule-cancel-button').click();
    await expect(modal).toBeHidden();
    await expect(ruleRow(page, 'STARBUCKS')).toHaveCount(0);
  });

  test('the rule modal counts what a pattern matches', async ({ page }) => {
    await recordTransaction(page, 'PAY Countdown Ponsonby');
    await recordTransaction(page, 'Rent');

    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await page.getByTestId('new-rule-button').click();
    const modal = ruleModal(page);
    await expect(modal).toBeVisible();
    const pattern = modal.getByTestId('rule-pattern-input');
    const count = modal.getByTestId('rule-match-count');

    await pattern.fill('countdown');
    await expect(count).toHaveText('Matches 1 of 2 transactions');
    await expect(modal.getByTestId('rule-match-samples')).toHaveText(
      'PAY Countdown Ponsonby',
    );

    await pattern.fill('nothing like this');
    await expect(count).toHaveText('Matches 0 of 2 transactions');

    // Enter saves the typed pattern straight away; the count is not awaited.
    await pattern.fill('Countdown');
    await pattern.press('Enter');
    await expect(modal).toBeHidden();
    await expect(ruleRow(page, 'Countdown')).toBeVisible();
  });

  test('runs rules over untagged transactions', async ({ page }) => {
    await recordTransaction(page, 'PAY Countdown Ponsonby');
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'Countdown');

    await page.getByTestId('tag-untagged-button').click();
    await expect(toast(page, 'Tagged 1 untagged transaction')).toBeVisible();

    // Re-tag runs only once confirmed; the rule still wins, so nothing changes.
    await page.getByTestId('retag-all-button').click();
    const retagModal = page.getByTestId('retag-modal');
    await expect(retagModal).toBeVisible();
    await retagModal.getByTestId('retag-confirm-button').click();
    await expect(retagModal).toBeHidden();
    await expect(
      toast(page, 'Tagged 0, changed 0, and cleared 0 transactions'),
    ).toBeVisible();

    await page.goto('/transactions');
    const row = page
      .locator('[data-testid="transaction-row"]')
      .filter({ hasText: 'PAY Countdown Ponsonby' });
    await expect(row).toContainText('Groceries');
    await row.getByRole('button', { name: 'Edit' }).click();
    await expect(page.getByTestId('transaction-rule-tag-hint')).toBeVisible();
  });

  test('editing a rule can move it to another tag', async ({ page }) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'STARBUCKS');
    await createTag(page, 'Transport');
    await tagRow(page, 'Groceries').click();

    await ruleRow(page, 'STARBUCKS').getByRole('button', { name: 'Edit' })
      .click();
    const modal = ruleModal(page);
    await expect(modal).toBeVisible();
    await modal.getByTestId('rule-tag-select').selectOption({
      label: 'Transport',
    });
    await modal.getByTestId('rule-submit-button').click();
    await expect(modal).toBeHidden();

    // The rule left Groceries and now lives under Transport.
    await expect(page.getByTestId('rules-panel')).toContainText(
      'No rules for "Groceries" yet',
    );
    await tagRow(page, 'Transport').click();
    await expect(ruleRow(page, 'STARBUCKS')).toHaveCount(1);
  });

  test('shows saved tags and rules after a reload', async ({ page }) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'STARBUCKS');

    await page.reload();

    await expect(tagRow(page, 'Groceries')).toBeVisible();
    await expect(ruleRow(page, 'STARBUCKS')).toBeVisible();
  });
});
