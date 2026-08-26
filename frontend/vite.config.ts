import path from 'path';
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, '.', 'VITE_');
    const apiProxyTarget =
      env.VITE_API_PROXY_TARGET || process.env.VITE_API_PROXY_TARGET || 'http://localhost:7071';
    return {
      server: {
        port: 7000,
        host: '0.0.0.0',
        proxy: {
          '/health': {
            target: apiProxyTarget,
            changeOrigin: true,
          },
          '/api': {
            target: apiProxyTarget,
            changeOrigin: true,
          },
        },
      },
      // Never `define` a secret here: anything in `define` is inlined into the
      // public bundle. Server-side keys stay in backend config, never in Vite.
      plugins: [react()],
      resolve: {
        alias: {
          '@': path.resolve(__dirname, '.'),
        }
      }
    };
});
