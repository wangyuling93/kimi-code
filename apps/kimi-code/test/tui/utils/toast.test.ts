import type { Component, OverlayHandle, OverlayOptions, TUI } from '@moonshot-ai/pi-tui';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { showToast } from '#/tui/utils/toast';

describe('showToast', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('mounts a non-capturing top-right overlay and auto-dismisses it', () => {
    const hide = vi.fn();
    const showOverlay = vi.fn<(component: Component, options?: OverlayOptions) => OverlayHandle>(
      () => ({ hide }) as unknown as OverlayHandle,
    );
    const tui = { showOverlay } as unknown as TUI;

    showToast(tui, 'Copied to clipboard');

    expect(showOverlay).toHaveBeenCalledTimes(1);
    const [component, options] = showOverlay.mock.calls[0]!;
    expect(options).toMatchObject({ anchor: 'top-right', nonCapturing: true, width: 23 });
    expect(component.render(80).length).toBe(1);
    expect(component.render(80)[0]).toContain('Copied to clipboard');
    expect(hide).not.toHaveBeenCalled();

    vi.advanceTimersByTime(3000);
    expect(hide).toHaveBeenCalledTimes(1);
  });

  it('honors a custom duration', () => {
    const hide = vi.fn();
    const tui = {
      showOverlay: vi.fn<(component: Component, options?: OverlayOptions) => OverlayHandle>(
        () => ({ hide }) as unknown as OverlayHandle,
      ),
    } as unknown as TUI;

    showToast(tui, 'hi', { durationMs: 500 });
    vi.advanceTimersByTime(499);
    expect(hide).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(hide).toHaveBeenCalledTimes(1);
  });
});
