// tests/client/languageForPath.test.ts
import { describe, it, expect } from 'vitest';
import { languageForPath } from '../../src/client/highlight/languageForPath';

describe('languageForPath', () => {
  it('maps known extensions to a language id', () => {
    expect(languageForPath('main.py')).toBe('python');
    expect(languageForPath('server.go')).toBe('go');
    expect(languageForPath('lib.rs')).toBe('rust');
    expect(languageForPath('init.lua')).toBe('lua');
    expect(languageForPath('build.sh')).toBe('bash');
    expect(languageForPath('config.yaml')).toBe('yaml');
    expect(languageForPath('config.YML')).toBe('yaml');
  });

  it('matches well-known extensionless filenames case-insensitively', () => {
    expect(languageForPath('Dockerfile')).toBe('dockerfile');
    expect(languageForPath('/project/Makefile')).toBe('makefile');
  });

  it('falls back to plaintext for unknown/absent extensions', () => {
    expect(languageForPath('notes.txt')).toBe('plaintext');
    expect(languageForPath('notes.log')).toBe('plaintext');
    expect(languageForPath('README')).toBe('plaintext');
    expect(languageForPath('.gitignore')).toBe('plaintext');
    expect(languageForPath('file.unknownext')).toBe('plaintext');
  });

  it('looks at the final path segment, not the whole path', () => {
    expect(languageForPath('C:\\repos\\mdview.nvim\\main.lua')).toBe('lua');
  });
});
