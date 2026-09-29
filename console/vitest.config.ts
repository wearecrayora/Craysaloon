import path from 'node:path';
import { defineConfig } from 'vitest/config';

// Tests are plain logic (money, scrubbing) and run in Node. They must not load
// vite.config.ts, whose Cloudflare plugin only works for the Worker build.
export default defineConfig({
  resolve: { alias: { '@': path.resolve(import.meta.dirname, '.') } },
  test: { include: ['lib/**/*.test.ts'] },
});
