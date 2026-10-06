// TESTS/client/spotlightMirror.test.ts
// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  applySpotlights,
  clearSpotlights,
  collectTextGroups,
  createSpotlightMirror,
  findMatches,
  parseSpotlightState,
  setSpotlightColors,
  type SpotlightItem,
  type SpotlightState,
} from '../../src/client/render/spotlightMirror';

// jsdom has no layout and no CSS Custom Highlight API, so what is pinned here is
// what the feature is made of: WHICH text gets matched (literal, case-sensitive,
// substrings, across inline markup, never across blocks) and WHAT ends up on it
// (marks in the fallback painter; ranges and priorities in the highlight painter,
// driven through a stand-in registry).

const item = (over: Partial<SpotlightItem> & { text: string }): SpotlightItem => ({
  slot: 1,
  line: false,
  kind: 'literal',
  ignoreCase: false,
  ...over,
});

const stateOf = (items: SpotlightItem[], max = 500): SpotlightState => ({
  items,
  colors: [],
  max,
});

let root: HTMLElement;

function mount(html: string): HTMLElement {
  document.body.innerHTML = `<div id="mdview-root">${html}</div>`;
  root = document.getElementById('mdview-root') as HTMLElement;
  return root;
}

/** The text each painted mark covers, with its classes. */
function marks(): { text: string; cls: string }[] {
  return Array.from(root.querySelectorAll('mark[data-mdview-spotlight]')).map(m => ({
    text: m.textContent ?? '',
    cls: m.className,
  }));
}

afterEach(() => {
  document.body.innerHTML = '';
  document.documentElement.removeAttribute('style');
});

describe('parseSpotlightState', () => {
  it('accepts what Neovim sends', () => {
    const s = parseSpotlightState({
      type: 'spotlight',
      items: [{ text: 'SYSsystosca', slot: 3, line: true, kind: 'word', ignoreCase: true }],
      colors: [{ slot: 3, fg: '#112233', bg: '#aabbcc', bold: true }],
      max: 42,
    });
    expect(s.items).toEqual([
      { text: 'SYSsystosca', slot: 3, line: true, kind: 'word', ignoreCase: true },
    ]);
    expect(s.colors).toEqual([{ slot: 3, fg: '#112233', bg: '#aabbcc', bold: true }]);
    expect(s.max).toBe(42);
  });

  it('defaults to case-sensitive substring matching, as in Neovim', () => {
    const [it0] = parseSpotlightState({ items: [{ text: 'x', slot: 1 }] }).items;
    expect(it0.kind).toBe('literal');
    expect(it0.ignoreCase).toBe(false);
    expect(it0.line).toBe(false);
  });

  it('treats anything that is not an object as the empty state', () => {
    for (const bad of [null, undefined, 'x', 3, false, []]) {
      expect(parseSpotlightState(bad).items).toEqual([]);
    }
  });

  it('drops malformed items one by one instead of painting something wrong', () => {
    const s = parseSpotlightState({
      items: [
        { text: '', slot: 1 }, // empty
        { text: 'a', slot: 0 }, // slots are 1..8
        { text: 'b', slot: 9 },
        { text: 'c', slot: 1.5 },
        { text: 5, slot: 1 },
        null,
        'x',
        { text: 'good', slot: 8 },
      ],
    });
    expect(s.items.map(i => i.text)).toEqual(['good']);
  });

  it('never lets a color through that is not a plain hex value', () => {
    const s = parseSpotlightState({
      colors: [
        { slot: 1, fg: 'red', bg: 'url(javascript:alert(1))' },
        { slot: 2, fg: '#12345', bg: '#1234567' },
        { slot: 3, fg: '#abcdef', bg: '#abcdef80' },
        { slot: 99, fg: '#000000', bg: '#000000' },
      ],
    });
    expect(s.colors).toHaveLength(3);
    expect(s.colors[0]).toMatchObject({ slot: 1, fg: undefined, bg: undefined });
    expect(s.colors[1]).toMatchObject({ slot: 2, fg: undefined, bg: undefined });
    expect(s.colors[2]).toMatchObject({ slot: 3, fg: '#abcdef', bg: '#abcdef80' });
  });

  it('repairs a bad match limit to the default and bounds a huge one', () => {
    expect(parseSpotlightState({ max: 0 }).max).toBe(500);
    expect(parseSpotlightState({ max: 'many' }).max).toBe(500);
    expect(parseSpotlightState({ max: 12.7 }).max).toBe(12);
    expect(parseSpotlightState({ max: 1e12 }).max).toBeLessThanOrEqual(100_000);
  });
});

describe('findMatches', () => {
  const find = (text: string, needle: string, over: Partial<SpotlightItem> = {}, limit = 100) =>
    findMatches(text, item({ text: needle, ...over }), limit);

  it('is case-sensitive by default', () => {
    expect(find('Foo foo FOO', 'foo').matches).toEqual([{ start: 4, end: 7 }]);
  });

  it('matches case-insensitively when the spotlight says so', () => {
    expect(find('Foo foo FOO', 'foo', { ignoreCase: true }).matches).toHaveLength(3);
  });

  it('matches substrings with no word boundaries (a visual-selection spotlight)', () => {
    expect(find('xSYSsystoscay', 'SYSsystosca').matches).toHaveLength(1);
    expect(find('abcabc', 'bc').matches).toHaveLength(2);
  });

  it('matches only between word boundaries for a word spotlight', () => {
    const w = { kind: 'word' as const };
    expect(find('foo food foo_ _foo foo.', 'foo', w).matches).toEqual([
      { start: 0, end: 3 },
      { start: 19, end: 22 },
    ]);
    expect(find('xfoo foox', 'foo', w).matches).toEqual([]);
  });

  it('treats a non-ASCII letter as a word character', () => {
    expect(find('äfoo foo', 'foo', { kind: 'word' }).matches).toEqual([{ start: 5, end: 8 }]);
  });

  it('never matches a word spotlight whose text starts or ends outside a word', () => {
    // `\<.foo\>` cannot match: `\<` needs a word character at the start.
    expect(find('a .foo b', '.foo', { kind: 'word' }).matches).toEqual([]);
  });

  it('takes the text literally, never as a regex', () => {
    expect(find('400 (Bad Request) 4xx', '400 (Bad Request)').matches).toHaveLength(1);
    expect(find('a.c abc', 'a.c').matches).toEqual([{ start: 0, end: 3 }]);
    expect(find('a.c abc', 'a.c', { ignoreCase: true }).matches).toEqual([{ start: 0, end: 3 }]);
    expect(find('x*y', '*').matches).toHaveLength(1);
  });

  it('does not overlap matches, left to right', () => {
    expect(find('aaaa', 'aa').matches).toEqual([
      { start: 0, end: 2 },
      { start: 2, end: 4 },
    ]);
  });

  it('stops at the limit and says more existed', () => {
    const r = find('ab ab ab ab', 'ab', {}, 2);
    expect(r.matches).toHaveLength(2);
    expect(r.capped).toBe(true);
  });

  it('does not call it capped when the limit was exactly enough', () => {
    expect(find('ab ab', 'ab', {}, 2).capped).toBe(false);
  });

  it('with a limit of 0 only reports whether anything is there', () => {
    expect(find('ab', 'ab', {}, 0)).toEqual({ matches: [], capped: true });
    expect(find('cd', 'ab', {}, 0)).toEqual({ matches: [], capped: false });
  });

  it('finds nothing for an empty needle or a too-short haystack', () => {
    expect(find('abc', '').matches).toEqual([]);
    expect(find('a', 'abc').matches).toEqual([]);
  });
});

describe('collectTextGroups', () => {
  it('joins the text of inline markup and keeps blocks apart', () => {
    mount('<p>an <code>error</code> here</p><p>second</p>');
    expect(collectTextGroups(root).map(g => g.text)).toEqual(['an error here', 'second']);
  });

  it('keeps table cells and list items apart', () => {
    mount('<table><tr><td>a</td><td>b</td></tr></table><ul><li>x</li><li>y</li></ul>');
    expect(collectTextGroups(root).map(g => g.text)).toEqual(['a', 'b', 'x', 'y']);
  });

  it('treats <br> as a line break', () => {
    mount('<p>one<br>two</p>');
    expect(collectTextGroups(root).map(g => g.text)).toEqual(['one', 'two']);
  });

  it('never searches script, style or form text', () => {
    mount(
      '<p>shown</p><script>hidden()</script><style>.hidden{}</style><textarea>typed</textarea>',
    );
    expect(collectTextGroups(root).map(g => g.text)).toEqual(['shown']);
  });

  it('skips whitespace-only groups', () => {
    mount('<ul>\n<li>x</li>\n</ul>');
    expect(collectTextGroups(root).map(g => g.text)).toEqual(['x']);
  });

  it('marks groups inside <pre> so lines can be told apart', () => {
    mount('<p>a</p><pre><code>l1\nl2</code></pre>');
    expect(collectTextGroups(root).map(g => g.pre)).toEqual([false, true]);
  });
});

describe('applySpotlights (<mark> painter)', () => {
  it('wraps each match in <mark class="spotlight spotlight-N">', () => {
    mount('<p>a token and another token</p>');
    const stats = applySpotlights(root, stateOf([item({ text: 'token', slot: 3 })]), 'marks');
    expect(marks()).toEqual([
      { text: 'token', cls: 'spotlight spotlight-3' },
      { text: 'token', cls: 'spotlight spotlight-3' },
    ]);
    expect(stats).toEqual({ items: 1, matches: 2, capped: 0 });
    expect(root.textContent).toBe('a token and another token'); // text itself untouched
  });

  it('finds text in <code> and <pre>', () => {
    mount('<p>use <code>SYSsystosca</code></p><pre><code>400 (Bad Request)\nok</code></pre>');
    applySpotlights(
      root,
      stateOf([item({ text: 'SYSsystosca' }), item({ text: '400 (Bad Request)', slot: 2 })]),
      'marks',
    );
    expect(marks().map(m => m.text)).toEqual(['SYSsystosca', '400 (Bad Request)']);
  });

  it('finds a token a code highlighter split across <span>s', () => {
    mount(
      '<pre><code><span class="hljs-keyword">const</span> <span class="hljs-title">answer</span> = 42</code></pre>',
    );
    applySpotlights(root, stateOf([item({ text: 'const answer' })]), 'marks');
    // one mark per text node the match crosses; together they cover the match
    expect(marks().map(m => m.text)).toEqual(['const', ' ', 'answer']);
    expect(root.textContent).toBe('const answer = 42');
  });

  it('is case-sensitive: the same word in another case stays unmarked', () => {
    mount('<p>Error error ERROR</p>');
    applySpotlights(root, stateOf([item({ text: 'error' })]), 'marks');
    expect(marks().map(m => m.text)).toEqual(['error']);
  });

  it('marks substrings without word boundaries, like Neovim', () => {
    mount('<p>prefixTOKENsuffix</p>');
    applySpotlights(root, stateOf([item({ text: 'TOKEN' })]), 'marks');
    expect(marks().map(m => m.text)).toEqual(['TOKEN']);
  });

  it('respects word boundaries for a word spotlight', () => {
    mount('<p>id idx id</p>');
    applySpotlights(root, stateOf([item({ text: 'id', kind: 'word' })]), 'marks');
    expect(marks()).toHaveLength(2);
  });

  it('does not match across two blocks', () => {
    mount('<p>foo</p><p>bar</p>');
    applySpotlights(root, stateOf([item({ text: 'foobar' }), item({ text: 'foo\nbar' })]), 'marks');
    expect(marks()).toEqual([]);
  });

  it('does not touch script or style content', () => {
    mount('<p>x</p><script>var token = 1;</script>');
    applySpotlights(root, stateOf([item({ text: 'token' })]), 'marks');
    expect(marks()).toEqual([]);
  });

  it('highlights the whole line in a <pre> for a line spotlight', () => {
    mount('<pre><code>first line\nthe token here\nlast</code></pre>');
    applySpotlights(root, stateOf([item({ text: 'token', slot: 2, line: true })]), 'marks');
    // The line is tinted around the match, which is painted on top of it: the
    // rest of the line is its own marks, and the other lines are untouched.
    expect(marks()).toEqual([
      { text: 'the ', cls: 'spotlight spotlight-2 spotlight-line' },
      { text: 'token', cls: 'spotlight spotlight-2' },
      { text: ' here', cls: 'spotlight spotlight-2 spotlight-line' },
    ]);
    expect(root.textContent).toBe('first line\nthe token here\nlast');
  });

  it('highlights the whole block for a line spotlight outside <pre>', () => {
    mount('<p>one</p><p>a token inside</p>');
    applySpotlights(root, stateOf([item({ text: 'token', line: true })]), 'marks');
    expect(marks()).toEqual([
      { text: 'a ', cls: 'spotlight spotlight-1 spotlight-line' },
      { text: 'token', cls: 'spotlight spotlight-1' },
      { text: ' inside', cls: 'spotlight spotlight-1 spotlight-line' },
    ]);
  });

  it('lets a match win over a line highlight where they overlap', () => {
    mount('<p>a token b</p>');
    applySpotlights(
      root,
      stateOf([item({ text: 'token', slot: 1, line: true }), item({ text: 'a', slot: 2 })]),
      'marks',
    );
    // "token" (slot 1 match) and the lone "a" (slot 2 match) outrank the line.
    const byText = Object.fromEntries(marks().map(m => [m.text, m.cls]));
    expect(byText['token']).toBe('spotlight spotlight-1');
    expect(byText['a']).toBe('spotlight spotlight-2');
    expect(root.textContent).toBe('a token b');
  });

  it('lets the higher slot win between two overlapping matches', () => {
    mount('<p>abcdef</p>');
    applySpotlights(
      root,
      stateOf([item({ text: 'abcd', slot: 1 }), item({ text: 'cdef', slot: 2 })]),
      'marks',
    );
    expect(marks()).toEqual([
      { text: 'ab', cls: 'spotlight spotlight-1' },
      { text: 'cdef', cls: 'spotlight spotlight-2' },
    ]);
    expect(root.textContent).toBe('abcdef');
  });

  it('caps the matches per spotlight and reports it', () => {
    mount('<p>x x x x x x x x</p>');
    const stats = applySpotlights(root, stateOf([item({ text: 'x' })], 3), 'marks');
    expect(marks()).toHaveLength(3);
    expect(stats).toEqual({ items: 1, matches: 3, capped: 1 });
  });

  it('applies the cap per spotlight, not in total', () => {
    mount('<p>x x x y y y</p>');
    const stats = applySpotlights(
      root,
      stateOf([item({ text: 'x' }), item({ text: 'y', slot: 2 })], 2),
      'marks',
    );
    expect(marks()).toHaveLength(4);
    expect(stats.capped).toBe(2);
  });

  it('restores the DOM exactly when cleared', () => {
    const html = '<p>a <em>token</em> and <code>token</code></p><pre><code>x token y</code></pre>';
    mount(html);
    applySpotlights(root, stateOf([item({ text: 'token', line: true })]), 'marks');
    expect(marks().length).toBeGreaterThan(0);
    clearSpotlights(root);
    expect(root.innerHTML).toBe(html);
    // and the text nodes are whole again, so a second search sees the same text
    expect(collectTextGroups(root).map(g => g.text)).toEqual(['a token and token', 'x token y']);
  });

  it('replaces the previous painting instead of stacking on it', () => {
    mount('<p>one two</p>');
    applySpotlights(root, stateOf([item({ text: 'one' })]), 'marks');
    applySpotlights(root, stateOf([item({ text: 'two', slot: 4 })]), 'marks');
    expect(marks()).toEqual([{ text: 'two', cls: 'spotlight spotlight-4' }]);
  });

  it('paints nothing for an empty state and removes what was there', () => {
    mount('<p>token</p>');
    applySpotlights(root, stateOf([item({ text: 'token' })]), 'marks');
    const stats = applySpotlights(root, stateOf([]), 'marks');
    expect(marks()).toEqual([]);
    expect(stats).toEqual({ items: 0, matches: 0, capped: 0 });
  });

  it('survives a character outside the BMP', () => {
    mount('<p>log 😀 token 😀</p>');
    applySpotlights(root, stateOf([item({ text: '😀 token' })]), 'marks');
    expect(marks().map(m => m.text)).toEqual(['😀 token']);
  });
});

// A stand-in for the CSS Custom Highlight API, which jsdom does not have.
class FakeHighlight {
  priority = 0;
  ranges: Range[] = [];
  add(range: Range): this {
    this.ranges.push(range);
    return this;
  }
}

describe('applySpotlights (CSS Custom Highlight API painter)', () => {
  let registry: Map<string, FakeHighlight>;

  beforeEach(() => {
    registry = new Map();
    const g = globalThis as unknown as Record<string, unknown>;
    g.CSS = { highlights: registry };
    g.Highlight = FakeHighlight;
  });

  afterEach(() => {
    const g = globalThis as unknown as Record<string, unknown>;
    delete g.CSS;
    delete g.Highlight;
  });

  const texts = (name: string): string[] =>
    (registry.get(name)?.ranges ?? []).map(r => r.toString());

  it('leaves the DOM exactly as it was and registers one highlight per slot', () => {
    const html = '<p>a token and another token</p>';
    mount(html);
    applySpotlights(root, stateOf([item({ text: 'token', slot: 3 })]));
    expect(root.innerHTML).toBe(html);
    expect([...registry.keys()]).toEqual(['spotlight-3']);
    expect(texts('spotlight-3')).toEqual(['token', 'token']);
  });

  it('builds ranges across inline markup', () => {
    mount('<pre><code><span>const</span> <span>answer</span> = 1</code></pre>');
    applySpotlights(root, stateOf([item({ text: 'const answer' })]));
    expect(texts('spotlight-1')).toEqual(['const answer']);
  });

  it('puts line highlights under match highlights', () => {
    mount('<pre><code>one\nthe token\nthree</code></pre>');
    applySpotlights(root, stateOf([item({ text: 'token', slot: 2, line: true })]));
    expect(texts('spotlight-line-2')).toEqual(['the token']);
    expect(texts('spotlight-2')).toEqual(['token']);
    const line = registry.get('spotlight-line-2');
    const match = registry.get('spotlight-2');
    expect(match && line && match.priority > line.priority).toBe(true);
  });

  it('ranks a higher slot above a lower one', () => {
    mount('<p>ab</p>');
    applySpotlights(root, stateOf([item({ text: 'a', slot: 1 }), item({ text: 'b', slot: 5 })]));
    const low = registry.get('spotlight-1');
    const high = registry.get('spotlight-5');
    expect(low && high && high.priority > low.priority).toBe(true);
  });

  it('removes a highlight whose spotlight is gone', () => {
    mount('<p>one two</p>');
    applySpotlights(
      root,
      stateOf([item({ text: 'one', slot: 1 }), item({ text: 'two', slot: 2 })]),
    );
    expect([...registry.keys()].sort()).toEqual(['spotlight-1', 'spotlight-2']);
    applySpotlights(root, stateOf([item({ text: 'two', slot: 2 })]));
    expect([...registry.keys()]).toEqual(['spotlight-2']);
    clearSpotlights(root);
    expect(registry.size).toBe(0);
  });

  it('can be forced onto marks even where the API exists', () => {
    mount('<p>token</p>');
    applySpotlights(root, stateOf([item({ text: 'token' })]), 'marks');
    expect(registry.size).toBe(0);
    expect(marks()).toHaveLength(1);
  });
});

describe('setSpotlightColors', () => {
  it('publishes the palette as CSS custom properties', () => {
    setSpotlightColors([
      { slot: 1, fg: '#000000', bg: '#ffee00', bold: false },
      { slot: 2, bg: '#00ff00', bold: true },
    ]);
    const style = document.documentElement.style;
    expect(style.getPropertyValue('--spotlight-1-bg')).toBe('#ffee00');
    expect(style.getPropertyValue('--spotlight-1-fg')).toBe('#000000');
    expect(style.getPropertyValue('--spotlight-2-bg')).toBe('#00ff00');
    expect(style.getPropertyValue('--spotlight-2-weight')).toBe('700');
    expect(style.getPropertyValue('--spotlight-2-fg')).toBe('');
  });

  it('replaces the previous palette, so a colorscheme change really updates the colors', () => {
    setSpotlightColors([{ slot: 1, fg: '#111111', bg: '#222222', bold: true }]);
    setSpotlightColors([{ slot: 1, bg: '#333333', bold: false }]);
    const style = document.documentElement.style;
    expect(style.getPropertyValue('--spotlight-1-bg')).toBe('#333333');
    expect(style.getPropertyValue('--spotlight-1-fg')).toBe('');
    expect(style.getPropertyValue('--spotlight-1-weight')).toBe('');
  });
});

describe('createSpotlightMirror', () => {
  const message = (items: unknown[], extra: Record<string, unknown> = {}): string =>
    JSON.stringify({ type: 'spotlight', items, colors: [], max: 500, ...extra });

  it('paints a message, sets its colors, and logs what it did', () => {
    mount('<p>a token</p>');
    const log = vi.fn();
    const mirror = createSpotlightMirror(root, { log, mode: 'marks' });
    mirror.update(
      message([{ text: 'token', slot: 2 }], {
        colors: [{ slot: 2, fg: '#101010', bg: '#fedcba', bold: false }],
      }),
    );
    expect(marks().map(m => m.text)).toEqual(['token']);
    expect(document.documentElement.style.getPropertyValue('--spotlight-2-bg')).toBe('#fedcba');
    expect(log).toHaveBeenCalledWith('spotlight: 1 spotlight(s), 1 match(es)');
  });

  it('removes the highlights when a later message has no items (clear, remove, set switch)', () => {
    mount('<p>a token</p>');
    const mirror = createSpotlightMirror(root, { mode: 'marks' });
    mirror.update(message([{ text: 'token', slot: 1 }]));
    expect(marks()).toHaveLength(1);
    mirror.update(message([]));
    expect(marks()).toEqual([]);
  });

  it('switches from one set of spotlights to another in one message', () => {
    mount('<p>alpha beta</p>');
    const mirror = createSpotlightMirror(root, { mode: 'marks' });
    mirror.update(message([{ text: 'alpha', slot: 1 }]));
    mirror.update(message([{ text: 'beta', slot: 2 }]));
    expect(marks().map(m => m.text)).toEqual(['beta']);
  });

  it('paints again after a re-render replaced the DOM', () => {
    mount('<p>old token</p>');
    const mirror = createSpotlightMirror(root, { mode: 'marks' });
    mirror.update(message([{ text: 'token', slot: 1 }]));

    root.innerHTML = '<p>new token and token</p>'; // what a render does
    expect(marks()).toEqual([]);
    mirror.reapply();
    expect(marks().map(m => m.text)).toEqual(['token', 'token']);
  });

  it('paints a state that arrived before the first render once the render happens', () => {
    mount('mdview loading…');
    const mirror = createSpotlightMirror(root, { mode: 'marks' });
    mirror.update(message([{ text: 'token', slot: 1 }]));
    expect(marks()).toEqual([]);

    root.innerHTML = '<p>a token</p>';
    mirror.reapply();
    expect(marks()).toHaveLength(1);
  });

  it('treats a malformed message as "nothing to paint", never as the old state', () => {
    mount('<p>a token</p>');
    const mirror = createSpotlightMirror(root, { mode: 'marks' });
    mirror.update(message([{ text: 'token', slot: 1 }]));
    mirror.update('{not json');
    expect(marks()).toEqual([]);
    expect(mirror.state().items).toEqual([]);
  });

  it('reports a spotlight cut off at the match limit', () => {
    mount('<p>x x x x x</p>');
    const log = vi.fn();
    const mirror = createSpotlightMirror(root, { log, mode: 'marks' });
    mirror.update(message([{ text: 'x', slot: 1 }], { max: 2 }));
    expect(marks()).toHaveLength(2);
    expect(log).toHaveBeenCalledWith('spotlight: 1 spotlight(s), 2 match(es), 1 capped at 2');
  });

  it('does not log the same line twice in a row', () => {
    mount('<p>a token</p>');
    const log = vi.fn();
    const mirror = createSpotlightMirror(root, { log, mode: 'marks' });
    const msg = message([{ text: 'token', slot: 1 }]);
    mirror.update(msg);
    mirror.update(msg);
    mirror.reapply();
    expect(log).toHaveBeenCalledTimes(1);
  });

  it('clear() removes the highlights and the colors', () => {
    mount('<p>a token</p>');
    const mirror = createSpotlightMirror(root, { mode: 'marks' });
    mirror.update(
      message([{ text: 'token', slot: 1 }], {
        colors: [{ slot: 1, fg: '#000000', bg: '#ffffff', bold: false }],
      }),
    );
    mirror.clear();
    expect(marks()).toEqual([]);
    expect(document.documentElement.style.getPropertyValue('--spotlight-1-bg')).toBe('');
    expect(mirror.state().items).toEqual([]);
  });

  it('a colorscheme change re-sends colors only: the highlights stay and the colors move', () => {
    mount('<p>a token</p>');
    const mirror = createSpotlightMirror(root, { mode: 'marks' });
    const items = [{ text: 'token', slot: 1 }];
    mirror.update(message(items, { colors: [{ slot: 1, bg: '#111111', bold: false }] }));
    mirror.update(message(items, { colors: [{ slot: 1, bg: '#222222', bold: false }] }));
    expect(marks()).toHaveLength(1);
    expect(document.documentElement.style.getPropertyValue('--spotlight-1-bg')).toBe('#222222');
  });
});
