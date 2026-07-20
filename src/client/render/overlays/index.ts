// src/client/render/overlays/index.ts
//
// Registers the built-in overlays and re-exports the manager surface. Import
// this once at boot; adding an overlay means writing the module and registering
// it here (plus its name in the Lua manifest, so :MDViewOverlay knows it).

import { registerOverlay } from './manager';
import { tocOverlay } from './toc';

registerOverlay(tocOverlay);

export {
  initOverlays,
  setOverlay,
  setOverlays,
  notifyCursor,
  notifyRender,
  dispatchOverlayControl,
  overlayNames,
  activeOverlayNames,
  registerOverlay,
  resetOverlays,
} from './manager';
export type { Overlay, OverlayCtx } from './types';
