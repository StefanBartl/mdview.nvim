// TESTS/client/langStatus.dom.test.ts
// @vitest-environment jsdom
//
// The badge that says the preview shows a translation (browser.display_lang):
// parsing of the control payload, the label per state, show/update/remove.

import { describe, it, expect, beforeEach } from 'vitest';
import {
  applyLangStatus,
  langStatusLabel,
  parseLangStatus,
} from '../../src/client/render/langStatus';

describe('parseLangStatus', () => {
  it('reads a status object and drops fields of the wrong type', () => {
    expect(
      parseLangStatus({
        state: 'translating',
        lang: 'en',
        engine: 'google',
        done: 3,
        total: 12,
        message: 5,
      }),
    ).toEqual({
      state: 'translating',
      lang: 'en',
      engine: 'google',
      done: 3,
      total: 12,
      message: undefined,
    });
  });

  it('treats false, null, junk and unknown states as "no badge"', () => {
    expect(parseLangStatus(false)).toBeNull();
    expect(parseLangStatus(null)).toBeNull();
    expect(parseLangStatus('x')).toBeNull();
    expect(parseLangStatus({ state: 'weird' })).toBeNull();
    expect(parseLangStatus({})).toBeNull();
  });
});

describe('langStatusLabel', () => {
  it('names the language, engine and progress while translating', () => {
    expect(
      langStatusLabel({ state: 'translating', lang: 'en', engine: 'google', done: 3, total: 12 }),
    ).toBe('Translating to en via google … 3/12');
  });

  it('says the original is shown when it failed', () => {
    expect(langStatusLabel({ state: 'failed', message: 'engine down' })).toBe(
      'Original, translation failed: engine down',
    );
  });

  it('says translated when done', () => {
    expect(langStatusLabel({ state: 'done', lang: 'en', engine: 'deepl' })).toBe(
      'Translated to en via deepl',
    );
  });
});

describe('applyLangStatus', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  it('adds one badge, updates it in place and removes it with null', () => {
    applyLangStatus(document, { state: 'translating', lang: 'en' });
    const badge = document.getElementById('mdview-lang-status');
    expect(badge?.textContent).toContain('Translating to en');
    expect(badge?.dataset.state).toBe('translating');

    applyLangStatus(document, { state: 'done', lang: 'en' });
    expect(document.querySelectorAll('#mdview-lang-status').length).toBe(1);
    expect(document.getElementById('mdview-lang-status')?.textContent).toBe('Translated to en');

    applyLangStatus(document, null);
    expect(document.getElementById('mdview-lang-status')).toBeNull();
  });
});
