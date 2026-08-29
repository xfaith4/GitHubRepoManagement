import { useEffect, useRef } from 'react';

/**
 * Whether a control can actually be focused right now.
 *
 * Deliberately not `offsetParent !== null`, the usual shorthand: jsdom has no
 * layout engine and reports `offsetParent` as null for everything, so that
 * check silently classifies every control as hidden and the trap degrades to
 * doing nothing -- under test AND anywhere else without layout. Worse, a test
 * suite cannot detect that degradation, because the no-op still "passes" any
 * assertion about where focus ended up.
 *
 * `checkVisibility()` is the real answer where it exists (it accounts for
 * `content-visibility` and ancestor clipping that attributes cannot express).
 * The fallback is an explicit attribute and computed-style walk, chosen
 * because every step of it is expressible in jsdom and therefore testable.
 */
function isVisible(el: HTMLElement): boolean {
  if (el.hasAttribute('hidden')) return false;
  if (el.closest('[hidden], [aria-hidden="true"], [inert]')) return false;

  const withCheck = el as HTMLElement & { checkVisibility?: (opts?: object) => boolean };
  if (typeof withCheck.checkVisibility === 'function') {
    return withCheck.checkVisibility({ contentVisibilityAuto: true, visibilityProperty: true });
  }

  const style = window.getComputedStyle(el);
  return style.display !== 'none' && style.visibility !== 'hidden';
}

/**
 * Escape-to-close, a focus trap, and focus restoration for a modal dialog.
 *
 * A dialog that can only be left by finding the X costs the operator a mouse
 * trip every time, and a dialog that leaks Tab focus to the page behind it is
 * a keyboard user's dead end: the page under an overlay is still focusable,
 * so Tab walks into content that is visually covered and cannot be seen.
 *
 * This is deliberately one hook rather than an edit in each dialog. Twenty
 * modal components ship in this console and exactly one of them handled
 * Escape; fixing them individually would be twenty chances to drift on what
 * "closed" means. The behavior belongs to the dialog pattern, not to any
 * dialog.
 *
 * Usage: attach the returned ref to the dialog PANEL (not the backdrop), and
 * pass the same `onClose` the backdrop and the Cancel button call.
 *
 *   const panelRef = useDialogDismiss<HTMLDivElement>(isOpen, onClose);
 *   ...
 *   <div ref={panelRef} role="dialog" aria-modal="true">
 */
export function useDialogDismiss<T extends HTMLElement>(
  isOpen: boolean,
  onClose: () => void,
): React.RefObject<T | null> {
  const panelRef = useRef<T | null>(null);
  // Held in a ref so a caller passing an inline arrow does not re-run the
  // effect on every render and re-steal focus mid-interaction.
  const onCloseRef = useRef(onClose);
  useEffect(() => { onCloseRef.current = onClose; }, [onClose]);

  useEffect(() => {
    if (!isOpen) return;

    // Whatever had focus when the dialog opened gets it back on close, so
    // dismissing returns the operator to the control they opened it from
    // rather than to the top of the document.
    const previouslyFocused = document.activeElement as HTMLElement | null;
    // Captured for the cleanup path specifically: by teardown React may have
    // already detached the ref, and cleanup still needs to ask whether this
    // dialog owned focus. The live ref is what the keydown handler reads,
    // because dialog bodies here fill in asynchronously.
    const panelAtOpen = panelRef.current;

    // Focusable descendants, recomputed per keystroke: dialog bodies here are
    // async (auth status, scan results), so a list captured on open goes stale
    // the moment content arrives.
    const focusable = (): HTMLElement[] => {
      const panel = panelRef.current;
      if (!panel) return [];
      const selector =
        'a[href], button:not([disabled]), textarea:not([disabled]), ' +
        'input:not([disabled]):not([type="hidden"]), select:not([disabled]), ' +
        '[tabindex]:not([tabindex="-1"])';
      return Array.from(panel.querySelectorAll<HTMLElement>(selector)).filter(isVisible);
    };

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        onCloseRef.current();
        return;
      }
      if (event.key !== 'Tab') return;

      const elements = focusable();
      if (elements.length === 0) return;
      const first = elements[0];
      const last = elements[elements.length - 1];
      const active = document.activeElement as HTMLElement | null;

      // Wrap at the ends, and pull focus back in if it has already escaped the
      // panel (a click on the backdrop leaves activeElement on <body>).
      if (event.shiftKey && (active === first || !panelRef.current?.contains(active))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (active === last || !panelRef.current?.contains(active))) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown);

    // Move focus into the dialog on open, but only if it is not already there:
    // a dialog that re-mounts on a state change must not yank focus out of the
    // field being typed into.
    const panel = panelRef.current;
    if (panel && !panel.contains(document.activeElement)) {
      const target = focusable()[0] ?? panel;
      if (target === panel && !panel.hasAttribute('tabindex')) panel.setAttribute('tabindex', '-1');
      target.focus();
    }

    return () => {
      document.removeEventListener('keydown', onKeyDown);
      if (!previouslyFocused) return;

      // Restore only if the dialog still owned focus. Two shapes count as
      // owning it: focus is literally inside the panel, or it has fallen back
      // to <body>, which is what the browser does when the focused node is
      // removed — the ordinary close path, and the one a naive `contains`
      // check misses entirely. Anything else means the operator has already
      // moved on to a real control, and restoring would steal from them.
      const active = document.activeElement;
      const dialogOwnedFocus =
        active === null || active === document.body || Boolean(panelAtOpen?.contains(active));
      if (dialogOwnedFocus) previouslyFocused.focus?.();
    };
  }, [isOpen]);

  return panelRef;
}

export default useDialogDismiss;
