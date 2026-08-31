import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

// TaskRadar backend (Fastify), started separately via `cd backend && npm run dev`.
const BACKEND_URL = "http://localhost:3001";

// TaskRadar is deliberately online-only (see README: offline editing/sync is
// an explicitly deferred feature, not an oversight). The service worker
// below exists purely to precache the built app shell (JS/CSS/HTML/icons)
// for faster repeat loads on a phone -- it must NEVER cache API responses or
// serve a stale API response / fake "offline" experience. These are exactly
// the path prefixes the dev proxy above forwards to the backend, i.e. every
// route the Fastify API serves (see backend/src/routes/*).
const API_PATH_PREFIXES = ["/health", "/auth", "/projects", "/tasks", "/notes"];
const apiPathPattern = new RegExp(`^(${API_PATH_PREFIXES.map((p) => p.replace("/", "\\/")).join("|")})`);

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      // Exercise the PWA in `npm run dev` too (not just in a production
      // build), so a phone hitting the dev server over LAN actually gets a
      // manifest + service worker to test against. vite-plugin-pwa runs this
      // through a separate dev-only SW build, so it doesn't fight Vite's HMR.
      devOptions: {
        enabled: true,
        type: "module",
      },
      manifest: {
        name: "TaskRadar",
        short_name: "TaskRadar",
        description: "Personal project/task tracker for a morning glance at everything in flight.",
        // Matches src/index.css: --color-accent is the app's one interactive
        // brand color (buttons, focus rings, the "current task" highlight);
        // --color-bg is the page background, used here as the splash-screen
        // background while the app shell loads.
        theme_color: "#2f6fed",
        background_color: "#f6f6f7",
        display: "standalone",
        start_url: "/",
        lang: "ru",
        icons: [
          { src: "/pwa-192x192.png", sizes: "192x192", type: "image/png", purpose: "any" },
          { src: "/pwa-512x512.png", sizes: "512x512", type: "image/png", purpose: "any" },
          { src: "/maskable-icon-512x512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
      workbox: {
        // Default globPatterns already only match the built static output
        // (dist/**/*.{js,css,html,svg,png,...}) -- there is no API response
        // in that directory to accidentally precache. No runtimeCaching
        // entries are added below, so the generated service worker never
        // registers a fetch handler for API calls: they hit the network
        // exactly as if the SW weren't installed.
        //
        // Defense in depth: also explicitly forbid the SPA's offline
        // "navigate to index.html" fallback from ever answering for an API
        // path, in case a future change starts issuing a navigation request
        // (e.g. a full-page link) at one of these prefixes.
        navigateFallbackDenylist: [apiPathPattern],
      },
    }),
  ],
  server: {
    // Bind 0.0.0.0, not just localhost: a later iteration needs a phone on the
    // same Wi-Fi to reach this dev server.
    host: true,
    proxy: {
      // Forwarding these to the backend makes the browser see everything as
      // same-origin, so the httpOnly session cookie round-trips correctly with
      // zero CORS configuration needed anywhere. Frontend code must fetch
      // relative paths (e.g. "/projects"), never an absolute backend URL --
      // that would bypass this proxy and also break on a phone, which can't
      // resolve "localhost" to this PC.
      "/health": BACKEND_URL,
      "/auth": BACKEND_URL,
      "/projects": BACKEND_URL,
      "/tasks": BACKEND_URL,
      "/notes": BACKEND_URL,
    },
  },
});
