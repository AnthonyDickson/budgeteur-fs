import { type Page } from '@playwright/test';

import { expect, test } from '../support/fixtures';
import { screenshotPath } from '../support/screenshot';

/// Create the first tag through the tagging UI. Each test starts with no data
/// (see support/fixtures.ts), so the tagging page shows the empty state.
async function createFirstTag(page: Page, name: string) {
  await page.goto('/tagging');
  await page.getByTestId('create-first-tag-button').click();

  const modal = page.getByTestId('tag-modal');
  await expect(modal).toBeVisible();
  await modal.getByTestId('tag-name-input').fill(name);
  await modal.getByTestId('tag-submit-button').click();
  await expect(modal).toBeHidden();
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

const queueRow = (page: Page, description: string) =>
  page.getByTestId('quick-tag-row').filter({ hasText: description });

test.describe('quick tagging', () => {
  test('tags, marks transfers, and dismisses with one click each', async ({
    page,
  }, testInfo) => {
    await createFirstTag(page, 'Groceries');
    await recordTransaction(page, 'Countdown');
    await recordTransaction(page, 'ATM withdrawal');
    await recordTransaction(page, 'To savings');

    await page.getByTestId('quick-tag-link').click();
    await expect(page.getByTestId('quick-tag-waiting')).toHaveText(
      '3 transactions are waiting for a tag',
    );

    // Found by role and name: the choices are native buttons, which Vimium's
    // link hints find.
    const groceries = queueRow(page, 'Countdown').getByRole('button', {
      name: 'Groceries',
    });
    await groceries.click();
    await expect(groceries).toHaveAttribute('aria-pressed', 'true');

    const dismiss = queueRow(page, 'ATM withdrawal').getByRole('button', {
      name: 'Dismiss',
    });
    await dismiss.click();
    await expect(dismiss).toHaveAttribute('aria-pressed', 'true');

    const transfer = queueRow(page, 'To savings').getByRole('button', {
      name: 'Transfer',
    });
    await transfer.click();
    await expect(transfer).toHaveAttribute('aria-pressed', 'true');

    await expect(page.getByTestId('quick-tag-waiting')).toHaveText(
      '0 transactions are waiting for a tag',
    );
    await page.screenshot({
      path: screenshotPath(testInfo, 'quick-tagged'),
      fullPage: true,
    });

    await page.reload();
    await expect(page.getByTestId('quick-tag-empty-state')).toBeVisible();

    await page.goto('/transactions');
    await expect(
      page
        .locator('[data-testid="transaction-row"]')
        .filter({ hasText: 'Countdown' }),
    ).toContainText('Groceries');
    await expect(
      page
        .locator('[data-testid="transaction-row"]')
        .filter({ hasText: 'To savings' }),
    ).toContainText('Transfer');
  });

  test('a transfer rule suggests transfers, approved together', async ({
    page,
  }, testInfo) => {
    // The rule panels show once the user has a tag.
    await createFirstTag(page, 'Groceries');
    await page.getByTestId('transfers-row').click();
    await expect(page.getByTestId('transfer-rules-note')).toBeVisible();
    await page.getByTestId('new-rule-button').click();
    const ruleModal = page.getByTestId('rule-modal');
    await expect(ruleModal.getByTestId('rule-tag-select')).toHaveValue(
      'transfer',
    );
    await ruleModal.getByTestId('rule-pattern-input').fill('SAVINGS TOP UP');
    await ruleModal.getByTestId('rule-submit-button').click();
    await expect(ruleModal).toBeHidden();
    await expect(
      page.getByTestId('rule-row').filter({ hasText: 'SAVINGS TOP UP' }),
    ).toBeVisible();

    await recordTransaction(page, 'Savings top up 1');
    await recordTransaction(page, 'Savings top up 2');

    // A rule's transfer is only suggested, so a run leaves both untagged.
    await page.goto('/tagging');
    await page.getByTestId('tag-untagged-button').click();
    await expect(
      page
        .getByTestId('toast')
        .filter({ hasText: 'Tagged 0 untagged transactions' }),
    ).toBeVisible();

    await page.goto('/quick-tagging');
    const row = queueRow(page, 'Savings top up 1');
    await expect(row.getByTestId('quick-tag-suggestion')).toContainText(
      'SAVINGS TOP UP',
    );
    await expect(row.getByRole('button', { name: 'Transfer' })).toHaveAttribute(
      'data-suggested',
      'true',
    );

    const count = page.getByTestId('quick-tag-suggestion-count');
    await expect(count).toHaveText(/Transfer\s*2/);
    await count.click();
    await expect(count).toHaveAttribute('aria-pressed', 'true');
    await page.screenshot({
      path: screenshotPath(testInfo, 'transfer-suggestions'),
      fullPage: true,
    });

    const approve = page.getByTestId('quick-tag-approve');
    // The busy label is rendered hidden beside the label, so the text contains
    // both.
    await expect(approve).toContainText('Mark 2 as transfers');
    await approve.click();
    await expect(
      page.getByTestId('toast').filter({ hasText: 'Marked 2 as transfers' }),
    ).toBeVisible();
    await expect(page.getByTestId('quick-tag-empty-state')).toBeVisible();

    await page.goto('/transactions');
    for (
      const description of [
        'Savings top up 1',
        'Savings top up 2',
      ]
    ) {
      await expect(
        page
          .locator('[data-testid="transaction-row"]')
          .filter({ hasText: description }),
      ).toContainText('Transfer');
    }
  });
});
