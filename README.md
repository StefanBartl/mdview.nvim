```sh
   ##     ## ########  ##     ## #### ######## ##      ##           ##    ## ##     ## #### ##     ##
   ###   ### ##     ## ##     ##  ##  ##       ##  ##  ##           ###   ## ##     ##  ##  ###   ###
   #### #### ##     ## ##     ##  ##  ##       ##  ##  ##           ####  ## ##     ##  ##  #### ####
   ## ### ## ##     ## ##     ##  ##  ######   ##  ##  ##           ## ## ## ##     ##  ##  ## ### ##
   ##     ## ##     ##  ##   ##   ##  ##       ##  ##  ##           ##  ####  ##   ##   ##  ##     ##
   ##     ## ##     ##   ## ##    ##  ##       ##  ##  ##    ###    ##   ###   ## ##    ##  ##     ##
   ##     ## ########     ###    #### ########  ###  ###     ###    ##    ##    ###    #### ##     ##
```

![version](https://img.shields.io/badge/version-0.9-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lazy.nvim](https://img.shields.io/badge/lazy.nvim-supported-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![TypeScript](https://img.shields.io/badge/client-TypeScript-3178C6.svg)
![Server](https://img.shields.io/badge/server-Node.js%20%7C%20Bun-43853D.svg)
![WASM](https://img.shields.io/badge/WASM-ready-654FF0.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)
![Performance](https://img.shields.io/badge/optimized-true-success.svg)
![Build](https://img.shields.io/badge/build-edge%20runtime-informational.svg)
![Contributions](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)

---

## Overview

**mdview.nvim** is a **browser-based Markdown preview plugin for Neovim**.
It provides a fast, real-time rendering pipeline powered by Node.js or Bun (future option),
and uses WebSocket communication to synchronize Markdown buffers with a live browser view.
- WebSocket - WASM - NodeJS - Bun -

**Key features:**
* Live browser preview for Markdown documents
* Automatic update on file changes or buffer switch
* Internal & external link resolution within project directories
* WASM-based rendering and syntax highlighting (planned)
* Lightweight TypeScript client with incremental DOM updates
* Written in Lua + TypeScript for portability and performance

---

## Development

To develop or contribute:

1. Clone the repository:

```bash
git clone https://github.com/StefanBartl/mdview.nvim
cd mdview.nvim
````

2. Load manually or via your preferred plugin manager.

3. Start the development server (default: Node.js runtime):

```bash
npm install
npm run dev
```

4. For Bun users (optional, experimental):

```bash
bun install
bun run dev
```

5. Make changes, test, and submit pull requests or open issues.

**Contributions are welcome** – whether it’s a bugfix, optimization, or new feature idea.

---

## Architecture

| Component         | Technology                       | Description                                          |
| ----------------- | -------------------------------- | ---------------------------------------------------- |
| **Core**          | Lua                              | Handles Neovim buffer events, state management, IPC  |
| **Server**        | Node.js (default) / Bun (future) | Local WebSocket + HTTP bridge for Markdown rendering |
| **Client**        | TypeScript / WASM                | Browser frontend with live DOM updates               |
| **Communication** | WebSocket                        | Real-time bidirectional updates                      |
| **Rendering**     | Markdown-It / markdown-wasm      | Fast Markdown → HTML transformation                  |

---

## License

[MIT License](./LICENSE)

---

## Disclaimer

ℹ️ mdview.nvim is under active development –
expect rapid iteration, experimental features, and evolving APIs.

---

## Feedback

Your feedback is very welcome!

Use the [GitHub Issue Tracker](https://github.com/StefanBartl/mdview.nvim/issues) to:

* Report bugs
* Suggest new features
* Ask usage questions
* Share thoughts on UI or workflow

For open discussion, visit the
[GitHub Discussions](https://github.com/StefanBartl/mdview.nvim/discussions).

If you find this plugin useful, please give it a ⭐ on GitHub to support its development.

---
