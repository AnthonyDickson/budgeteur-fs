import { test, expect } from '@playwright/test';

test.describe('todos', () => {
  test('shows empty list on first load', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('[data-testid="todo-item"]')).toHaveCount(0);
  });

  test('create a new todo', async ({ page }) => {
    await page.goto('/');

    await page.fill('[data-testid="new-todo-input"]', 'Buy milk');
    await page.press('[data-testid="new-todo-input"]', 'Enter');

    await expect(page.locator('[data-testid="todo-item"]')).toHaveCount(1);
    await expect(page.locator('[data-testid="todo-title"]')).toHaveText('Buy milk');
  });
});
