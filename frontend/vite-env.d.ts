/// <reference types="vite/client" />

// Injected by `define` in vite.config.ts at build time. Null when the build
// ran outside a git checkout — the chip renders "unknown", never a guess.
declare const __BUILD_COMMIT__: string | null;
declare const __BUILD_TIME__: string;
