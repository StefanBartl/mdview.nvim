// tests/client/fileKind.test.ts
import { describe, it, expect } from 'vitest';
import { isMarkdownPath } from '../../src/client/render/fileKind';

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
