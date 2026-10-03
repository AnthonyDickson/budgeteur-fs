import { expect, type Locator } from '@playwright/test';

/// Assert the amount rendered inside a container, independent of how it is
/// displayed. The money element carries its raw value in `data-amount`; parsing
/// it with `Number` keeps the expectation a plain JS number, so the currency
/// symbol, grouping, and separators are free to change.
///
/// The container must hold exactly one `[data-amount]` element.
export async function expectAmount(container: Locator, expected: number) {
  await expect
    .poll(async () => {
      const raw = await container
        .locator('[data-amount]')
        .getAttribute('data-amount');
      return raw === null ? null : Number(raw);
    })
    .toBe(expected);
}
