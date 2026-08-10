// Shared test cleanup: rm -rf with retry.
//
// A live server can finish a straggler async write into the dir just after
// close() returns; if that lands between `rm`'s recursive enumeration and the
// final rmdir, cleanup flakes with ENOTEMPTY. Retry the transient fs codes
// (same idiom as packages/minidb/test/cluster/helpers.ts).
import { rm } from 'node:fs/promises';

export async function rmrf(dir: string): Promise<void> {
  for (let attempt = 0; ; attempt++) {
    try {
      await rm(dir, { recursive: true, force: true });
      return;
    } catch (e) {
      const code = (e as NodeJS.ErrnoException).code;
      if (attempt >= 5 || (code !== 'ENOTEMPTY' && code !== 'EBUSY' && code !== 'EACCES' && code !== 'EPERM')) throw e;
      await new Promise((resolve) => setTimeout(resolve, 50 * (attempt + 1)));
    }
  }
}
