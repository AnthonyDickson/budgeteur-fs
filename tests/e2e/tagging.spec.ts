import { test, expect, type Page, type TestInfo } from '@playwright/test';

// The tagging page reads from both localStorage and the server. Each test gets
// a fresh browser context (so empty localStorage), and the dev-only reset
// endpoint clears the server's tags/rules, so every test starts from the empty
// state.
test.beforeEach(async ({ page }) => {
  const response = await page.request.delete('/api/test/tagging');
  expect(response.status()).toBe(204);
});

const screenshotPath = (testInfo: TestInfo, name: string) =>
  testInfo.outputPath(
    `${name}${testInfo.retry > 0 ? `.retry-${testInfo.retry}` : ''}.png`,
  );

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

/// Navigate to the tagging page and wait for the empty state. The reset in
/// `beforeEach` guarantees there are no tags, so this is deterministic.
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

test.describe('tagging', () => {
  test('creates the first tag from the empty state', async ({ page }, testInfo) => {
    await gotoEmptyTagging(page);

    await createFirstTag(page, 'Groceries', '#EF4444');

    await expect(page.getByTestId('no-tags-empty-state')).toBeHidden();
    await expect(page.getByTestId('tags-panel')).toBeVisible();

    // The newly created tag is selected and owns the rules panel.
    await expect(tagRow(page, 'Groceries')).toHaveAttribute('aria-current', 'true');
    await expect(page.getByTestId('rules-panel')).toContainText('Groceries');
    await expect(toast(page, "Created tag 'Groceries'")).toBeVisible();

    await page.screenshot({
      path: screenshotPath(testInfo, 'first-tag-created'),
      fullPage: true,
    });
  });

  test('manages a full tag and rule lifecycle', async ({ page }, testInfo) => {
    await gotoEmptyTagging(page);

    await createFirstTag(page, 'Groceries');
    await createTag(page, 'Transport');
    // The most recently created tag becomes selected.
    await expect(page.getByTestId('rules-panel')).toContainText('Transport');

    await createRule(page, 'STARBUCKS');
    await expect(toast(page, 'Created rule STARBUCKS')).toBeVisible();

    // Edit the rule's pattern.
    await ruleRow(page, 'STARBUCKS').getByRole('button', { name: 'Edit' }).click();
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
    await ruleRow(page, 'LATTE').getByRole('button', { name: 'Delete' }).click();
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
    await expect(tagRow(page, 'Groceries')).toHaveAttribute('aria-current', 'true');
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
    await expect(modal).toContainText('Name cannot be longer than 64 characters');
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

  test('rule patterns are unique per tag', async ({ page }) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'STARBUCKS');

    // The same pattern under the same tag is rejected.
    await page.getByTestId('new-rule-button').click();
    const modal = ruleModal(page);
    await expect(modal).toBeVisible();
    await modal.getByTestId('rule-pattern-input').fill('STARBUCKS');
    await modal.getByTestId('rule-submit-button').click();
    await expect(modal).toContainText(
      'A rule with this pattern already exists for this tag',
    );
    await modal.getByTestId('rule-cancel-button').click();
    await expect(modal).toBeHidden();

    // The same pattern under a different tag is allowed.
    await createTag(page, 'Transport');
    await createRule(page, 'STARBUCKS');
    await expect(ruleRow(page, 'STARBUCKS')).toHaveCount(1);

    // Groceries still owns its own rule.
    await tagRow(page, 'Groceries').click();
    await expect(ruleRow(page, 'STARBUCKS')).toHaveCount(1);
  });

  test('editing a rule can move it to another tag', async ({ page }) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'STARBUCKS');
    await createTag(page, 'Transport');
    await tagRow(page, 'Groceries').click();

    await ruleRow(page, 'STARBUCKS').getByRole('button', { name: 'Edit' }).click();
    const modal = ruleModal(page);
    await expect(modal).toBeVisible();
    await modal.getByTestId('rule-tag-select').selectOption({ label: 'Transport' });
    await modal.getByTestId('rule-submit-button').click();
    await expect(modal).toBeHidden();

    // The rule left Groceries and now lives under Transport.
    await expect(page.getByTestId('rules-panel')).toContainText(
      'No rules for "Groceries" yet',
    );
    await tagRow(page, 'Transport').click();
    await expect(ruleRow(page, 'STARBUCKS')).toHaveCount(1);
  });

  test('restores tags and rules after a reload', async ({ page }) => {
    await gotoEmptyTagging(page);
    await createFirstTag(page, 'Groceries');
    await createRule(page, 'STARBUCKS');

    await page.reload();

    await expect(tagRow(page, 'Groceries')).toBeVisible();
    await expect(ruleRow(page, 'STARBUCKS')).toBeVisible();
  });
});
