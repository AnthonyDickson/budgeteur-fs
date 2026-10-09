import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './specs',
  outputDir: 'test-results',
  timeout: 30000,
  // Every test is isolated (see support/fixtures.ts), so tests can run in any
  // order and in parallel. Each worker needs its own E2E user.
  fullyParallel: true,
  workers: 4,
  // Retries capture a trace; a test that only passes on retry still fails the run.
  retries: 1,
  failOnFlakyTests: true,
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:5173',
    ignoreHTTPSErrors: true,
    screenshot: 'on',
    trace: 'on-first-retry',
  },
});
