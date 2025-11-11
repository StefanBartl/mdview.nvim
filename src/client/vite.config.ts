// src/client/vite.config.ts
import { defineConfig } from 'vite';
import path from 'path';

const backendPort = process.env.MDVIEW_PORT || '43219';

export default defineConfig({
  root: path.resolve(__dirname),
  build: {
    outDir: path.resolve(__dirname, '../../dist/client'),
    emptyOutDir: true,
    rollupOptions: {
      input: path.resolve(__dirname, 'index.html'),
    },
  },
  server: {
    port: 43220,
    // Proxy websocket path /ws to the backend server running on backendPort
    proxy: {
      '/ws': {
        target: `ws://localhost:${backendPort}`,
        ws: true,
        changeOrigin: true,
        rewrite: path => path.replace(/^\/ws/, ''), // falls Backend nicht /ws erwartet
      },
      // Also proxy /render and other HTTP endpoints to backend during dev, so the browser can call /render directly.
      '/render': {
        target: `http://localhost:${backendPort}`,
        changeOrigin: true,
      },
      '/health': {
        target: `http://localhost:${backendPort}`,
        changeOrigin: true,
      },
    },
  },
});
