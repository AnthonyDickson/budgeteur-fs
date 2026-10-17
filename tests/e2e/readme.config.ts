import { defineConfig } from '@playwright/test';

import base from './playwright.config';

/// Captures the README's screenshots from mock data (`just readme-screenshots`).
/// Apart from the E2E specs, so the suite does not rewrite them.
export default defineConfig({
  ...base,
  testDir: './readme',
  workers: 1,
  retries: 0,
  use: { ...base.use, screenshot: 'off' },
});
