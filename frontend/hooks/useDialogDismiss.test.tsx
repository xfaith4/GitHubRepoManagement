// @vitest-environment jsdom
//
// The dismiss contract every dialog inherits. Worth testing once and properly:
// eighteen more modals still have to adopt this, and each one will trust these
// guarantees rather than re-deriving them.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import { useDialogDismiss } from './useDialogDismiss';

afterEach(cleanup);

/**
 * Three controls where the FIRST or the LAST can be hidden. Hiding a middle
 * control proves nothing: the trap only ever reads `first` and `last`, so a
 * no-op filter and a correct one agree on the endpoints. Hiding an endpoint is
 * what makes the two observably different.
 */
const EndpointDialog: React.FC<{ hideFirst?: boolean; hideLast?: boolean; how?: 'attr' | 'style' }> = ({
  hideFirst = false,
  hideLast = false,
  how = 'attr',
}) => {
  const panelRef = useDialogDismiss<HTMLDivElement>(true, () => {});
  const hide = (on: boolean) =>
    how === 'attr'
      ? { hidden: on }
      : { style: on ? ({ display: 'none' } as React.CSSProperties) : undefined };
  return (
    <div ref={panelRef} role="dialog" aria-modal="true" aria-label="Endpoints">
      <button {...hide(hideFirst)}>Alpha</button>
      <button>Beta</button>
      <button {...hide(hideLast)}>Gamma</button>
    </div>
  );
};

const Dialog: React.FC<{ isOpen: boolean; onClose: () => void }> = ({ isOpen, onClose }) => {
  const panelRef = useDialogDismiss<HTMLDivElement>(isOpen, onClose);
  if (!isOpen) return null;
  return (
    <div ref={panelRef} role="dialog" aria-modal="true" aria-label="Test dialog">
      <button>First</button>
      <button>Middle</button>
      <button>Last</button>
    </div>
  );
};

describe('useDialogDismiss', () => {
  it('closes on Escape', () => {
    const onClose = vi.fn();
    render(<Dialog isOpen onClose={onClose} />);
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('does not close on Escape while shut', () => {
    const onClose = vi.fn();
    render(<Dialog isOpen={false} onClose={onClose} />);
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).not.toHaveBeenCalled();
  });

  it('moves focus into the dialog on open', () => {
    render(<Dialog isOpen onClose={() => {}} />);
    expect(screen.getByRole('button', { name: 'First' })).toHaveFocus();
  });

  it('wraps Tab from the last control back to the first', () => {
    render(<Dialog isOpen onClose={() => {}} />);
    screen.getByRole('button', { name: 'Last' }).focus();
    fireEvent.keyDown(document, { key: 'Tab' });
    expect(screen.getByRole('button', { name: 'First' })).toHaveFocus();
  });

  it('wraps Shift+Tab from the first control back to the last', () => {
    render(<Dialog isOpen onClose={() => {}} />);
    screen.getByRole('button', { name: 'First' }).focus();
    fireEvent.keyDown(document, { key: 'Tab', shiftKey: true });
    expect(screen.getByRole('button', { name: 'Last' })).toHaveFocus();
  });

  it('pulls focus back in when it has escaped the panel', () => {
    render(
      <>
        <button>Outside</button>
        <Dialog isOpen onClose={() => {}} />
      </>,
    );
    screen.getByRole('button', { name: 'Outside' }).focus();
    fireEvent.keyDown(document, { key: 'Tab' });
    expect(screen.getByRole('button', { name: 'First' })).toHaveFocus();
  });

  it('restores focus to the opener on close', () => {
    const Harness: React.FC = () => {
      const [open, setOpen] = React.useState(false);
      return (
        <>
          <button onClick={() => setOpen(true)}>Opener</button>
          <Dialog isOpen={open} onClose={() => setOpen(false)} />
        </>
      );
    };
    render(<Harness />);
    const opener = screen.getByRole('button', { name: 'Opener' });
    opener.focus();
    fireEvent.click(opener);
    expect(screen.getByRole('button', { name: 'First' })).toHaveFocus();

    fireEvent.keyDown(document, { key: 'Escape' });
    expect(opener).toHaveFocus();
  });

  // The visibility filter itself. Every assertion here FAILS if isVisible is
  // replaced with `() => true`, which the earlier tests did not -- verified by
  // neutering it and watching these go red.
  describe('visibility filter', () => {
    it.each([['the hidden attribute', 'attr' as const], ['display:none', 'style' as const]])(
      'skips a first control hidden by %s when placing initial focus',
      (_label, how) => {
        render(<EndpointDialog hideFirst how={how} />);
        // A no-op filter would focus Alpha here.
        expect(screen.getByRole('button', { name: 'Beta' })).toHaveFocus();
      },
    );

    it.each([['the hidden attribute', 'attr' as const], ['display:none', 'style' as const]])(
      'treats the last VISIBLE control as the wrap point when the last is hidden by %s',
      (_label, how) => {
        render(<EndpointDialog hideLast how={how} />);
        screen.getByRole('button', { name: 'Beta' }).focus();
        fireEvent.keyDown(document, { key: 'Tab' });
        // Beta is the last visible control, so Tab wraps to Alpha. A no-op
        // filter would consider Gamma last, leave Beta mid-list, and not move
        // focus at all.
        expect(screen.getByRole('button', { name: 'Alpha' })).toHaveFocus();
      },
    );

    it('keeps every control focusable when none is hidden', () => {
      render(<EndpointDialog />);
      expect(screen.getByRole('button', { name: 'Alpha' })).toHaveFocus();
      fireEvent.keyDown(document, { key: 'Tab', shiftKey: true });
      expect(screen.getByRole('button', { name: 'Gamma' })).toHaveFocus();
    });
  });
});
