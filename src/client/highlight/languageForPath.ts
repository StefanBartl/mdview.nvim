// src/client/highlight/languageForPath.ts
//
// Maps a document path to a `language-xxx` class for the plain-text preview
// path (render/plainText.ts): the same class shape comrak already emits for
// fenced code blocks, so highlight/hljs.ts and highlight/shiki.ts need no
// changes — they already just read `pre code`'s `language-*` class. IDs are
// picked to exist in both `highlight.js/lib/common`'s bundle and Shiki's
// `bundledLanguages`; where the two disagree, shiki.ts's own langOf() falls
// back to plain text rather than throwing.

const EXT_LANG: Record<string, string> = {
  ts: 'typescript',
  tsx: 'typescript',
  js: 'javascript',
  jsx: 'javascript',
  mjs: 'javascript',
  cjs: 'javascript',
  py: 'python',
  go: 'go',
  rs: 'rust',
  lua: 'lua',
  sh: 'bash',
  bash: 'bash',
  zsh: 'bash',
  json: 'json',
  jsonc: 'json',
  yaml: 'yaml',
  yml: 'yaml',
  toml: 'toml',
  c: 'c',
  h: 'c',
  cpp: 'cpp',
  hpp: 'cpp',
  cc: 'cpp',
  cxx: 'cpp',
  java: 'java',
  rb: 'ruby',
  php: 'php',
  css: 'css',
  scss: 'scss',
  html: 'html',
  htm: 'html',
  xml: 'xml',
  sql: 'sql',
  ps1: 'powershell',
  vim: 'vim',
  diff: 'diff',
  ini: 'ini',
};

// Well-known extensionless filenames, matched case-insensitively.
const NAME_LANG: Record<string, string> = {
  dockerfile: 'dockerfile',
  makefile: 'makefile',
};

// A real "no highlighting" language id in both hljs and Shiki, used
// explicitly for unknown/absent extensions rather than leaving the class
// off — an absent class would trigger highlight.js's own content
// auto-detection, which is exactly what we don't want for plain text.
const PLAINTEXT = 'plaintext';

/** `language-xxx` id for `path`'s extension/filename, or "plaintext". */
export function languageForPath(path: string): string {
  const base = (path.split(/[/\\]/).pop() ?? path).toLowerCase();
  const named = NAME_LANG[base];
  if (named) return named;

  const dot = base.lastIndexOf('.');
  if (dot <= 0) return PLAINTEXT; // no extension, or a dotfile
  const ext = base.slice(dot + 1);
  return EXT_LANG[ext] ?? PLAINTEXT;
}
