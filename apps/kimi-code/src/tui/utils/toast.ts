import { visibleWidth } from '@moonshot-ai/pi-tui';
import type { Component, TUI } from '@moonshot-ai/pi-tui';

import { currentTheme } from '#/tui/theme';

const DEFAULT_TOAST_DURATION_MS = 3000;

/**
 * Transient toast notification rendered as a non-capturing overlay anchored
 * to the top-right corner of the terminal (opencode-style). It never steals
 * keyboard focus and auto-dismisses after a few seconds.
 */
class ToastMessage implements Component {
  constructor(private readonly message: string) {}

  invalidate(): void {}

  render(width: number): string[] {
    // Fill the whole overlay width with the background so the toast plate
    // hugs the surrounding border (corner) with no padding gap on either side.
    const text = ` ${this.message} `;
    const fill = ' '.repeat(Math.max(0, width - visibleWidth(text)));
    const label = currentTheme.bg('primary', currentTheme.boldFg('text', text + fill));
    return [label];
  }
}

/**
 * Show a top-right toast hugging the corner. Replaces any visible toast; the
 * previous one is dismissed immediately so stacked copy actions do not pile
 * up. The overlay is sized to the message so it does not occupy the default
 * 80-column overlay width.
 */
export function showToast(tui: TUI, message: string, options: { durationMs?: number } = {}): void {
  const durationMs = options.durationMs ?? DEFAULT_TOAST_DURATION_MS;
  const width = Math.min(60, message.length + 4);
  const handle = tui.showOverlay(new ToastMessage(message), {
    anchor: 'top-right',
    margin: { top: 1, right: 1 },
    nonCapturing: true,
    width,
  });
  const timer = setTimeout(() => handle.hide(), durationMs);
  timer.unref?.();
}
