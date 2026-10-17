import path from 'node:path';

import {
  type APIRequestContext,
  type Page,
  type TestInfo,
} from '@playwright/test';

import { expect, test } from '../support/fixtures';

/// Where the screenshots are saved; `just readme-screenshots` copies them to
/// docs/images.
const shot = (testInfo: TestInfo, name: string) =>
  path.join(testInfo.project.outputDir, 'readme', `${name}.png`);

/// The day `days` days before today.
function dayBefore(days: number): Date {
  const date = new Date();
  date.setDate(date.getDate() - days);
  return date;
}

/// A date `days` days before today, as YYYY-MM-DD.
function daysAgo(days: number): string {
  const date = dayBefore(days);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${
    pad(date.getDate())
  }`;
}

/// A repeatable sequence of numbers in [0, 1), so every run draws the same
/// mock data.
function random(seed: number): () => number {
  return () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
}

async function post(
  request: APIRequestContext,
  url: string,
  data: object,
): Promise<{ id: string }> {
  const response = await request.post(url, { data });
  expect(response.ok(), `POST ${url}: ${await response.text()}`).toBe(true);
  return response.json();
}

type Tag = { name: string; color: string; kind: 'Income' | 'Expense' };

const tags: Tag[] = [
  { name: 'Salary', color: 'Green', kind: 'Income' },
  { name: 'Rent', color: 'Peach', kind: 'Expense' },
  { name: 'Groceries', color: 'Yellow', kind: 'Expense' },
  { name: 'Eating out', color: 'Pink', kind: 'Expense' },
  { name: 'Transport', color: 'Sky', kind: 'Expense' },
  { name: 'Utilities', color: 'Lavender', kind: 'Expense' },
  { name: 'Subscriptions', color: 'Mauve', kind: 'Expense' },
];

/// Six months of a fictional household's accounts, assets, tags, and
/// transactions.
async function seed(request: APIRequestContext) {
  /// An account with one balance a month, oldest first, ending today.
  const account = async (name: string, number: string, balances: number[]) => {
    const { id } = await post(request, '/api/accounts', {
      name,
      number,
      term: 'Current',
      balance: null,
    });
    for (const [i, balance] of balances.entries()) {
      await post(request, `/api/accounts/${id}/observations`, {
        balance: balance.toFixed(2),
        asOf: daysAgo((balances.length - 1 - i) * 30),
      });
    }
    return id;
  };
  const everyday = await account(
    'Everyday',
    '12-3456-0123456-00',
    [2100, 1840, 2650, 2210, 2480, 2930, 2340.55],
  );
  await account(
    'Savings',
    '12-3456-0123456-01',
    [12000, 13500, 14200, 15600, 16300, 17400, 18250],
  );
  const card = await account(
    'Credit card',
    'XXXX-XXXX-XXXX-9010',
    [-640, -910, -720, -1180, -860, -1020, -1245.3],
  );

  /// A non-current item with one value a month, oldest first, ending today.
  const item = async (
    name: string,
    side: 'Asset' | 'Liability',
    values: number[],
  ) => {
    const { id } = await post(request, '/api/balance-sheet/items', {
      name,
      side,
      term: 'NonCurrent',
      value: values[0].toFixed(2),
      asOf: daysAgo((values.length - 1) * 30),
    });
    for (const [i, value] of values.slice(1).entries()) {
      await post(request, `/api/balance-sheet/items/${id}/observations`, {
        value: value.toFixed(2),
        asOf: daysAgo((values.length - 2 - i) * 30),
      });
    }
  };
  await item(
    'KiwiSaver',
    'Asset',
    [38200, 38900, 39750, 40100, 41020, 41800, 42650],
  );
  await item('Car', 'Asset', [14000, 13800, 13600, 13400, 13200, 13000, 12800]);
  await item(
    'Student loan',
    'Liability',
    [21400, 21000, 20600, 20200, 19800, 19400, 19000],
  );

  const tagIds = new Map<string, string>();
  for (const tag of tags) {
    tagIds.set(tag.name, (await post(request, '/api/tags', tag)).id);
  }

  const next = random(42);
  const transaction = (
    days: number,
    description: string,
    amount: number,
    tag: string | null,
    accountId = everyday,
  ) =>
    post(request, '/api/transactions', {
      amount: amount.toFixed(2),
      description,
      date: daysAgo(days),
      isTransfer: false,
      tagId: tag === null ? null : tagIds.get(tag),
      accountId,
    });

  for (let days = 180; days >= 0; days--) {
    if (days % 14 === 3) {
      await transaction(days, 'ACME LTD SALARY', 3850, 'Salary');
    }
    if (days % 7 === 1) {
      await transaction(days, 'HARBOUR PROPERTY RENT', -620, 'Rent');
    }
    if (dayBefore(days).getDay() === 6) {
      await transaction(
        days,
        'FRESHMART NEWTOWN',
        -(120 + next() * 60),
        'Groceries',
      );
    }
    if (next() < 0.25) {
      const place = ['BEAN THERE CAFE', 'NOODLE HOUSE', 'THE CORNER PIZZA'][
        Math.floor(next() * 3)
      ];
      await transaction(days, place, -(12 + next() * 45), 'Eating out', card);
    }
    if (days % 10 === 5) {
      await transaction(days, 'METRO CARD TOP UP', -40, 'Transport');
    }
    if (days % 30 === 12) {
      await transaction(days, 'CITY POWER', -(140 + next() * 50), 'Utilities');
      await transaction(days, 'FIBRENET BROADBAND', -79.99, 'Utilities');
      await transaction(days, 'STREAMFLIX', -18.99, 'Subscriptions', card);
    }
  }
  // Waiting in the quick tagging queue.
  await transaction(2, 'POS W/D HARDWARE BARN', -64.5, null, card);
  await transaction(1, 'ONLINE PAYMENT GIFT', -35, null);
}

/// Open `url` and wait for its data and charts to settle.
async function open(page: Page, url: string, heading: string) {
  await page.goto(url);
  await expect(page.getByRole('heading', { level: 1, name: heading }))
    .toBeVisible();
  await page.waitForLoadState('networkidle');
}

test('README screenshots', async ({ page, browser }, testInfo) => {
  test.setTimeout(120_000);
  await seed(page.request);

  await page.setViewportSize({ width: 1280, height: 900 });
  await open(page, '/', 'Dashboard');
  await page.screenshot({
    path: shot(testInfo, 'dashboard-desktop'),
    fullPage: true,
  });
  await open(page, '/transactions', 'Transactions');
  await page.screenshot({ path: shot(testInfo, 'transactions-desktop') });
  await open(page, '/balance-sheet', 'Balance Sheet');
  await page.screenshot({ path: shot(testInfo, 'balance-sheet-desktop') });
  await open(page, '/reports', 'Reports');
  await page.screenshot({ path: shot(testInfo, 'reports-desktop') });

  // The narrowest supported phone, as in the mobile spec.
  const phone = await browser.newContext({
    storageState: await page.context().storageState(),
    viewport: { width: 390, height: 664 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
  });
  const mobile = await phone.newPage();
  try {
    await open(mobile, '/', 'Dashboard');
    await mobile.screenshot({ path: shot(testInfo, 'dashboard-mobile') });
    await open(mobile, '/quick-tagging', 'Quick tagging');
    await mobile.screenshot({ path: shot(testInfo, 'quick-tagging-mobile') });
  } finally {
    await phone.close();
  }
});
