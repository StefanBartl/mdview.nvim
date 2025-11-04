import { defineConfig } from 'vite';
import path from 'path';

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
    // Proxy websocket path /ws to the backend server running on 43219
    proxy: {
      // forward HTTP and WS requests under /ws to backend
      '/ws': {
        target: 'ws://localhost:43219',
        ws: true,
        changeOrigin: true,
      },
    },
  },
});
