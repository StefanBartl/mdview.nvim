// src/client/render/controlMessage.ts
//
// The \x02 control message from Neovim (:MDViewCursor, :MDViewZoom, :MDView
// edit, a notice, ...): JSON with optional fields. parseControl keeps only the
// fields that have the right type, so applying them needs no further checks.

export interface ControlMessage {
  overlay?: { name: string; on: boolean };
  overlays?: Record<string, boolean>;
  overlayData?: { name: string; data: unknown };
  reveal?: boolean;
  cursor?: string;
  zoom?: number;
  /** True when the key is present at all: `false` removes the badge. */
  hasDisplayLang: boolean;
  displayLang?: unknown;
  blankLines?: boolean;
  /** Non-empty, cut to MAX_NOTICE_LENGTH. */
  notice?: string;
  editBlocks?: boolean;
  selectionSync?: boolean;
  /** True when the key is present at all: `false` clears the highlight. */
  hasSelection: boolean;
  selection?: unknown;
}

export const MAX_NOTICE_LENGTH = 200;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/** The control message in `json`, or null when it is not a JSON object. */
export function parseControl(json: string): ControlMessage | null {
  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch {
    return null;
  }
  if (!isObject(raw) || Array.isArray(raw)) return null;

  const msg: ControlMessage = {
    hasDisplayLang: 'displayLang' in raw,
    hasSelection: 'selection' in raw,
  };
  if (isObject(raw.overlay)) {
    const { name, on } = raw.overlay;
    if (typeof name === 'string' && typeof on === 'boolean') msg.overlay = { name, on };
  }
  if (isObject(raw.overlays)) msg.overlays = raw.overlays as Record<string, boolean>;
  if (isObject(raw.overlayData)) {
    const { name, data } = raw.overlayData;
    if (typeof name === 'string') msg.overlayData = { name, data };
  }
  if (typeof raw.reveal === 'boolean') msg.reveal = raw.reveal;
  if (typeof raw.cursor === 'string') msg.cursor = raw.cursor;
  if (typeof raw.zoom === 'number') msg.zoom = raw.zoom;
  if (msg.hasDisplayLang) msg.displayLang = raw.displayLang;
  if (typeof raw.blankLines === 'boolean') msg.blankLines = raw.blankLines;
  if (typeof raw.notice === 'string' && raw.notice !== '') {
    msg.notice = raw.notice.slice(0, MAX_NOTICE_LENGTH);
  }
  if (typeof raw.editBlocks === 'boolean') msg.editBlocks = raw.editBlocks;
  if (typeof raw.selectionSync === 'boolean') msg.selectionSync = raw.selectionSync;
  if (msg.hasSelection) msg.selection = raw.selection;
  return msg;
}
