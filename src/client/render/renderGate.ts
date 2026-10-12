// src/client/render/renderGate.ts
//
// Holds a render back while something in the DOM would be destroyed by it (an
// open block editor) and renders the newest held text once that is over.
//
// Only the newest text matters: texts that arrive while the gate is held
// replace each other, so a flush renders one document, never a backlog.

export interface RenderGateOptions {
  /** True while a render must not touch the DOM. */
  isHeld: () => boolean;
  /** Renders `text` into the DOM (and remembers it as the text on screen). */
  render: (text: string) => void;
}

export interface RenderGate {
  /** Render `text` now, or hold it back while the gate is held. */
  push: (text: string) => void;
  /**
   * The newest text there is: the one held back, else `shown` (the one on
   * screen). A re-render not caused by a push must start from this, or it
   * would put an older text back.
   */
  current: (shown: string) => string;
  /** True when a text is held back. */
  pending: () => boolean;
  /**
   * Render the held text, if any. Call it when the hold ends. Returns whether
   * something was rendered.
   */
  release: () => boolean;
}

export function createRenderGate(options: RenderGateOptions): RenderGate {
  let held: string | null = null;
  return {
    push(text) {
      if (options.isHeld()) {
        held = text;
        return;
      }
      held = null;
      options.render(text);
    },
    current: shown => held ?? shown,
    pending: () => held !== null,
    release() {
      if (held === null) return false;
      const text = held;
      held = null;
      options.render(text);
      return true;
    },
  };
}
