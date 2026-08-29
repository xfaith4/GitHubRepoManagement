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
          // `secure: false` because the portal terminates TLS with a
          // SELF-SIGNED certificate (scripts\New-RepoManagementTlsCertificate.ps1).
          // Without it, pointing VITE_API_PROXY_TARGET at an https portal fails
          // certificate validation inside the proxy and every /api call from
          // `npm run dev` dies with an opaque 500 that names nothing about TLS.
          //
          // The default below stays http: a fresh install serves plain HTTP by
          // design (`tlsState: disabled`). Once you enable TLS the portal stops
          // answering http entirely, so set the target explicitly:
          //   VITE_API_PROXY_TARGET=https://127.0.0.1:7071 npm run dev
          '/health': {
            target: apiProxyTarget,
            changeOrigin: true,
            secure: false,
          },
          '/api': {
            target: apiProxyTarget,
            changeOrigin: true,
            secure: false,
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
