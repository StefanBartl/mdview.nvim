// src/client/highlight/hljs.ts
//
// highlight.js implementation of code-fence highlighting. Lazy-loaded (see
// ./index.ts) so it's only pulled into the bundle when selected. The token
// colors come from hljs-theme.css (CSS variables → theme-aware); the code
// background is the active mdview theme's --md-code-block-bg.

import hljs from 'highlight.js/lib/common';
import './hljs-theme.css';

/**
 * Highlight every fenced code block under `root`. comrak emits
 * `<pre><code class="language-xxx">`; highlight.js reads that class and adds
 * `.hljs-*` spans, which hljs-theme.css colors. Blocks with an unknown/absent
 * language are highlighted with auto-detection off (left plain) to avoid
 * mislabeling prose. Runs on trusted, already-sanitized DOM, so the spans it
 * injects need no further sanitization.
 */
export function highlightAll(root: HTMLElement): void {
  root.querySelectorAll<HTMLElement>('pre code').forEach(el => {
    // Re-highlighting is guarded by hljs via the `data-highlighted` attribute;
    // after a re-render the nodes are fresh, so this always applies.
    hljs.highlightElement(el);
  });
}
