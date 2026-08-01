import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  outputDir: 'test-results',
  timeout: 30000,
  retries: 1,
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:5173',
    ignoreHTTPSErrors: true,
    screenshot: 'on',
    storageState: 'auth.json',
    trace: 'on-first-retry',
  },
  globalSetup: './global-setup.ts',
});
