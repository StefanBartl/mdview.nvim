- [ ] `package.json` anlegen (Projekt-Metadaten, Abhängigkeiten, dev-scripts)

Füge die folgende `package.json` als Ausgangspunkt hinzu (JSON darf keine Kommentare enthalten; Beschreibungen unten sind erläuternd auf Deutsch):

```json
{
  "name": "mdview.nvim",
  "version": "0.1.0",
  "private": true,
  "description": "Browser-based Markdown preview for Neovim (mdview.nvim) — Node.js default, Bun optional",
  "author": "Stefan Bartl",
  "license": "MIT",
  "engines": {
    "node": ">=18"
  },
  "scripts": {
    "dev": "concurrently \"npm:dev:server\" \"npm:dev:client\"",
    "dev:server": "ts-node-dev --respawn --transpile-only src/server/index.ts",
    "dev:client": "vite --config src/client/vite.config.ts",
    "start": "node ./dist/server/index.js",
    "build": "npm run build:server && npm run build:client",
    "build:server": "tsc -p tsconfig.server.json && esbuild src/server/index.ts --bundle --platform=node --outfile=dist/server/index.js --target=node18",
    "build:client": "vite build --config src/client/vite.config.ts",
    "lint": "eslint \"src/**/*.{ts,tsx,js}\" --fix",
    "format": "prettier --write \"src/**/*.{ts,js,json,md,css,scss}\"",
    "test": "vitest run",
    "check:types": "tsc -p tsconfig.json --noEmit",
    "prepare": "husky install"
  },
  {
   "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.13.0",
    "markdown-it": "^13.0.1",
    "markdown-it-anchor": "^8.6.6",
    "micromatch": "^4.0.8",
    "chokidar": "^3.5.3"
  },
  "devDependencies": {
    "typescript": "^5.6.2",
    "ts-node-dev": "^2.0.0",
    "esbuild": "^0.25.12",
    "vite": "^5.2.0",
    "eslint": "^9.39.0",
    "eslint-config-prettier": "^10.1.8",
    "prettier": "^3.0.0",
    "vitest": "^1.3.4",
    "@types/node": "^20.5.1",
    "@types/express": "^4.17.21",
    "concurrently": "^8.2.0",
    "husky": "^8.0.3"
  }}
```

Erläuterung (Deutsch):

- `dev` startet Server und Client parallel (concurrently).
- `dev:server` verwendet `ts-node-dev` für schnellen TypeScript-Dev-Workflow; spätere Alternative: Bun-Start-Script in `package.json` ergänzen.
- `build` erzeugt Server-Bundle (esbuild/tsc) und Client-Bundle (Vite).
- `test` nutzt `vitest`.
- Abhängigkeiten: `express` + `ws` für HTTP/WS; `markdown-it` + `markdown-it-anchor` für Markdown + Anchors; `chokidar` optional für Filewatch bei serverseitigem Watch.

______________________________________________________________________

- [ ] `tsconfig.json` (Gemeinsame TS Konfiguration für Client/Server)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Node",
    "lib": ["ES2022", "DOM"],
    "rootDir": ".",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "sourceMap": true,
    "outDir": "dist",
    "types": ["node"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

Optional: separate `tsconfig.server.json` mit `"module": "CommonJS"` / Node spezifischen Optionen falls gewünscht.

______________________________________________________________________

- [ ] `src/client/vite.config.ts` (Vite Dev Server Konfiguration — minimal)

```ts
import { defineConfig } from 'vite';

export default defineConfig({
  root: 'src/client',
  build: {
    outDir: '../../dist/client',
    emptyOutDir: true,
    rollupOptions: {
      input: '/src/client/index.html'
    }
  },
  server: {
    port: 43220
  }
});
```

______________________________________________________________________

- [ ] `.eslintrc.cjs` (Basis ESLint Konfiguration)

```js
module.exports = {
  root: true,
  env: {
    node: true,
    es2022: true,
    browser: true
  },
  extends: ['eslint:recommended', 'prettier'],
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: 'module'
  },
  rules: {
    'no-console': 'off'
  }
};
```

______________________________________________________________________

- [ ] `.prettierrc` (Prettier Basis)

```json
{
  "printWidth": 100,
  "tabWidth": 2,
  "useTabs": false,
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "arrowParens": "avoid"
}
```

______________________________________________________________________

- [ ] `.vscode/settings.json` (Empfehlung für Entwickler: Optional, wird standardmäßig `!.vscode/settings.json` in .gitignore behalten)

```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "typescript.tsdk": "node_modules/typescript/lib"
}
```

______________________________________________________________________

- [ ] Minimaler Server-Entrypoint (TypeScript) `src/server/index.ts` (Dev-Skeleton)

```ts
/* Minimal server skeleton for development.
   - Provides HTTP static folder for client
   - Provides WebSocket server for live updates
*/

import express from 'express';
import { WebSocketServer } from 'ws';
import path from 'path';

const app = express();
const PORT = Number(process.env.MDVIEW_PORT) || 43219;

app.use('/', express.static(path.join(process.cwd(), 'dist', 'client')));

const server = app.listen(PORT, () => {
  console.log(`mdview server running at http://localhost:${PORT}`);
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  console.log('client connected');
  ws.on('message', (msg) => {
    console.log('received', msg.toString());
  });
  ws.send(JSON.stringify({ type: 'hello', payload: 'mdview' }));
});
```

______________________________________________________________________

- [ ] Minimaler Client-Entrypoint `src/client/main.ts` (Dev-Skeleton)

```ts
/* Client bootstrapping:
   - Connects to WebSocket on server
   - Receives render updates (html) and injects into container
*/

const socket = new WebSocket(`ws://${location.host}`);

socket.addEventListener('open', () => {
  console.log('connected to mdview server');
});

socket.addEventListener('message', (ev) => {
  try {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'render_update' && typeof msg.payload === 'string') {
      const container = document.getElementById('mdview-root');
      if (container) {
        // replace or patch DOM; initial POC: full replace
        container.innerHTML = msg.payload;
      }
    }
  } catch (err) {
    console.error('invalid message', err);
  }
});
```

______________________________________________________________________

- [ ] Husky / Git Hooks (optional)

  - `npx husky add .husky/pre-commit "npm run lint && npm run format"` (prepare-Script in package.json sorgt für Installation)

______________________________________________________________________

- [ ] Checkliste zum Commit / Initialisierung (Checkboxen)
- [ ] `package.json` hinzufügen
- [ ] `tsconfig.json` hinzufügen
- [ ] `src/server/index.ts` (minimal) hinzufügen
- [ ] `src/client/index.html` + `src/client/main.ts` hinzufügen
- [ ] `.eslintrc.cjs` + `.prettierrc` hinzufügen
- [ ] `vite.config.ts` hinzufügen
- [ ] DevDependencies installieren (`npm ci` nach package.json)
- [ ] Erster Dev-Start testen: `npm run dev`

______________________________________________________________________

Empfehlung zur Default-Runtime (nochmal kurz):

- Standardmäßig **Node.js** als Default belassen, damit Nutzer nicht gezwungen wird, Bun zu installieren.
- Bun-Support als optionalen Startmodus / separate npm-script bzw. separate Anleitung in README (Roadmap-Meilenstein M3).

Nach dem Anlegen der oben genannten Dateien und dem `npm ci` kann der initiale Commit erstellt werden.
