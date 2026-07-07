import { describe } from 'bun:test';

export const browserE2EDisabledOnWindows =
  process.platform === 'win32' && process.env.BROWSE_RUN_BROWSER_E2E !== '1';

export const describeBrowserE2E = browserE2EDisabledOnWindows ? describe.skip : describe;

