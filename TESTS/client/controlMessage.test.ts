// tests/client/controlMessage.test.ts
//
// The control message keeps only fields of the right type.

import { describe, it, expect } from 'vitest';
import { MAX_NOTICE_LENGTH, parseControl } from '../../src/client/render/controlMessage';

describe('parseControl', () => {
  it('is null for anything that is not a JSON object', () => {
    expect(parseControl('')).toBeNull();
    expect(parseControl('{')).toBeNull();
    expect(parseControl('null')).toBeNull();
    expect(parseControl('3')).toBeNull();
    expect(parseControl('"x"')).toBeNull();
    expect(parseControl('[1]')).toBeNull();
  });

  it('reads the simple fields', () => {
    const msg = parseControl(
      '{"cursor":"caret","zoom":1.5,"reveal":true,"blankLines":false,"editBlocks":false,"selectionSync":true}',
    );
    expect(msg).toMatchObject({
      cursor: 'caret',
      zoom: 1.5,
      reveal: true,
      blankLines: false,
      editBlocks: false,
      selectionSync: true,
    });
  });

  it('drops fields of the wrong type', () => {
    const msg = parseControl(
      '{"cursor":1,"zoom":"2","reveal":"yes","blankLines":1,"editBlocks":"on","selectionSync":null,"notice":5}',
    )!;
    expect(msg.cursor).toBeUndefined();
    expect(msg.zoom).toBeUndefined();
    expect(msg.reveal).toBeUndefined();
    expect(msg.blankLines).toBeUndefined();
    expect(msg.editBlocks).toBeUndefined();
    expect(msg.selectionSync).toBeUndefined();
    expect(msg.notice).toBeUndefined();
  });

  it('keeps a notice as text, cut to the limit, and ignores an empty one', () => {
    expect(parseControl('{"notice":"Not applied"}')!.notice).toBe('Not applied');
    expect(parseControl('{"notice":""}')!.notice).toBeUndefined();
    const long = 'x'.repeat(MAX_NOTICE_LENGTH + 50);
    expect(parseControl(JSON.stringify({ notice: long }))!.notice).toHaveLength(MAX_NOTICE_LENGTH);
  });

  it('tells a missing displayLang / selection from a false one', () => {
    const none = parseControl('{}')!;
    expect(none.hasDisplayLang).toBe(false);
    expect(none.hasSelection).toBe(false);
    const off = parseControl('{"displayLang":false,"selection":false}')!;
    expect(off.hasDisplayLang).toBe(true);
    expect(off.displayLang).toBe(false);
    expect(off.hasSelection).toBe(true);
    expect(off.selection).toBe(false);
  });

  it('reads the cursor paragraph switch and tells a missing color from a cleared one', () => {
    const on = parseControl('{"cursorParagraph":true,"cursorParagraphBg":"#203040"}')!;
    expect(on.cursorParagraph).toBe(true);
    expect(on.hasCursorParagraphBg).toBe(true);
    expect(on.cursorParagraphBg).toBe('#203040');
    const cleared = parseControl('{"cursorParagraph":false,"cursorParagraphBg":false}')!;
    expect(cleared.cursorParagraph).toBe(false);
    expect(cleared.hasCursorParagraphBg).toBe(true);
    const none = parseControl('{"cursorParagraph":"yes"}')!;
    expect(none.cursorParagraph).toBeUndefined();
    expect(none.hasCursorParagraphBg).toBe(false);
  });

  it('checks the shape of the overlay fields', () => {
    expect(parseControl('{"overlay":{"name":"keycast","on":true}}')!.overlay).toEqual({
      name: 'keycast',
      on: true,
    });
    expect(parseControl('{"overlay":{"name":"keycast"}}')!.overlay).toBeUndefined();
    expect(parseControl('{"overlayData":{"name":"x","data":[1]}}')!.overlayData).toEqual({
      name: 'x',
      data: [1],
    });
    expect(parseControl('{"overlayData":{"data":1}}')!.overlayData).toBeUndefined();
    expect(parseControl('{"overlays":{"a":true}}')!.overlays).toEqual({ a: true });
  });
});
