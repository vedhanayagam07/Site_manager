// ==============================================================================
// TSR BUILDERS — SECURE PROGRESSIVE WEB APP SERVICE WORKER
// File: public/sw.js
// ==============================================================================
// SECURITY & PRIVACY SPECIFICATION:
// 1. Never caches authenticated Supabase API responses or user data.
// 2. Never caches non-GET requests (mutations flow via offline outbox).
// 3. Serves precached static assets (manifest, logo, offline fallback).
// 4. Provides network-first navigation with clean offline fallback page.
// ==============================================================================

const CACHE_NAME = "tsr-builders-pwa-v2";
const STATIC_ASSETS = [
  "/manifest.json",
  "/tsrlogo.png",
  "/offline.html"
];

// Install: Precache shell assets
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

// Activate: Purge obsolete cache versions
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

// Fetch: Strategy router with strict privacy boundary
self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // 1. PRIVACY BOUNDARY: Strictly bypass service worker for Supabase & API calls
  if (
    req.method !== "GET" ||
    url.hostname.includes("supabase.co") ||
    url.pathname.startsWith("/api/") ||
    url.pathname.includes("/auth/") ||
    url.pathname.includes("/rest/")
  ) {
    return; // Pass directly to network
  }

  // 2. Precached static assets (icons, manifest, offline page)
  if (STATIC_ASSETS.includes(url.pathname)) {
    event.respondWith(
      caches.match(req).then((cached) => cached || fetch(req))
    );
    return;
  }

  // 3. HTML Navigation requests: Network-first with offline fallback
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req).catch(() => {
        return caches.match("/offline.html").then((fallback) => {
          return fallback || new Response("Offline", { status: 503, headers: { "Content-Type": "text/plain" } });
        });
      })
    );
    return;
  }

  // 4. Other static assets (Next.js chunks, fonts, images)
  if (
    url.pathname.startsWith("/_next/static/") ||
    url.pathname.match(/\.(png|jpg|jpeg|svg|gif|webp|woff2?|css|js)$/i)
  ) {
    event.respondWith(
      caches.match(req).then((cached) => {
        if (cached) return cached;
        return fetch(req).then((response) => {
          if (response && response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, clone));
          }
          return response;
        });
      })
    );
  }
});
