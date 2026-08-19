/**
 * Release 2.9 — a tap equivalent for a hover-only definition.
 *
 * A `title` attribute is a mouse affordance. On a touch device it never
 * appears, so a definition that lives only in a title is not "subtle" on a
 * phone — it is absent. The audit found the definitions of change-aware
 * indexing, remote staleness, and dispatch readiness all reachable exclusively
 * by hover, on the same screens the operator is most likely to open away from
 * their desk.
 *
 * This renders the term with a small ⓘ button beside it. Tapping (or clicking,
 * or pressing Enter on) the button discloses the definition inline, below the
 * term, where it needs no pointer at all. The `title` stays on the button so
 * the desktop hover users already have keeps working — this adds a path, it
 * does not remove one.
 *
 * Inline disclosure rather than a floating popover, deliberately: a popover
 * needs positioning logic, an outside-click handler, and a viewport it can
 * escape on a 390px screen. Text that pushes the layout down has none of
 * those failure modes.
 */
import { useId, useState } from 'react';

interface DefinitionHintProps {
  /** The visible term being defined. */
  children: React.ReactNode;
  /** The definition itself — the text that used to live only in `title`. */
  definition: string;
  /** Optional class for the term's own span, so callers keep their styling. */
  className?: string;
  /** Test hook; the disclosure gets `${testId}-detail`. */
  'data-testid'?: string;
}

const DefinitionHint = ({ children, definition, className, 'data-testid': testId }: DefinitionHintProps) => {
  const [open, setOpen] = useState(false);
  const detailId = useId();

  return (
    <>
      <span className={className}>{children}</span>
      <button
        type="button"
        onClick={() => setOpen(v => !v)}
        aria-expanded={open}
        aria-controls={detailId}
        aria-label={open ? 'Hide definition' : 'Show definition'}
        title={definition}
        data-testid={testId}
        className="ml-1 align-middle text-gray-500 hover:text-gray-300 focus:outline-none focus:ring-1 focus:ring-blue-500 rounded"
      >
        ⓘ
      </button>
      {open && (
        <span
          id={detailId}
          role="note"
          data-testid={testId ? `${testId}-detail` : undefined}
          className="block mt-1 text-xs text-gray-400 font-normal"
        >
          {definition}
        </span>
      )}
    </>
  );
};

export default DefinitionHint;
