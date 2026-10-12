import { defineConfig } from 'vitest/config';
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers';

export default defineConfig(async () => ({
  plugins: [cloudflareTest({
    wrangler: { configPath: './wrangler.jsonc' },
    remoteBindings: false,
    miniflare: {
      bindings: {
        TEST_MIGRATIONS: await readD1Migrations('./migrations'),
        BETTER_AUTH_SECRET: 'local-test-only-not-a-production-secret-123456789',
        AUTH_BASE_URL: 'https://auth.test',
        SIGNUP_ENABLED: 'true',
      },
    },
  })],
  test: {
    setupFiles: ['./test/setup.ts'],
    testTimeout: 20000,
    hookTimeout: 20000,
    fileParallelism: false,
  },
}));
