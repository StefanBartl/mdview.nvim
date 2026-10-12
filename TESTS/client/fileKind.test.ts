// tests/client/fileKind.test.ts
import { describe, it, expect } from 'vitest';
import {
  isMarkdownPath,
  needsRerenderAfterDocChange,
  shownPath,
} from '../../src/client/render/fileKind';

describe('isMarkdownPath', () => {
  it('recognizes md/markdown/mdx, case-insensitively', () => {
    expect(isMarkdownPath('/docs/README.md')).toBe(true);
    expect(isMarkdownPath('/docs/README.MD')).toBe(true);
    expect(isMarkdownPath('notes.markdown')).toBe(true);
    expect(isMarkdownPath('page.mdx')).toBe(true);
  });

  it('rejects other extensions and extensionless files', () => {
    expect(isMarkdownPath('main.lua')).toBe(false);
    expect(isMarkdownPath('notes.txt')).toBe(false);
    expect(isMarkdownPath('Makefile')).toBe(false);
    expect(isMarkdownPath('.gitignore')).toBe(false);
    expect(isMarkdownPath('')).toBe(false);
  });

  it('looks at the final path segment, not the whole path', () => {
    expect(isMarkdownPath('C:\\repos\\mdview.nvim\\README.md')).toBe(true);
    expect(isMarkdownPath('/repos/mdview.nvim/main.lua')).toBe(false);
  });
});

describe('shownPath', () => {
  it('is the announced document, else the room path', () => {
    expect(shownPath('/b/other.md', '/a/first.lua')).toBe('/b/other.md');
    expect(shownPath(null, '/a/first.lua')).toBe('/a/first.lua');
    expect(shownPath('', '/a/first.lua')).toBe('/a/first.lua');
  });
});

describe('needsRerenderAfterDocChange', () => {
  it('is false before anything was rendered', () => {
    expect(needsRerenderAfterDocChange(null, '/a/x.md')).toBe(false);
  });

  it('is false for a Markdown document after a Markdown render', () => {
    expect(needsRerenderAfterDocChange(true, '/a/x.md')).toBe(false);
  });

  it('is true when the kind changed, in either direction', () => {
    expect(needsRerenderAfterDocChange(false, '/a/x.md')).toBe(true); // code view -> Markdown
    expect(needsRerenderAfterDocChange(true, '/a/x.lua')).toBe(true); // Markdown -> code view
  });

  it('is true for a code view, whose language comes from the path', () => {
    expect(needsRerenderAfterDocChange(false, '/a/x.lua')).toBe(true);
  });
});
