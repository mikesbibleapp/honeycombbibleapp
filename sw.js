// Service worker for Abide (mikesbibleapp)
// Network-first for the HTML so the home-screen PWA always picks up the
// latest deploy on launch, with a cached copy as the offline fallback.

const CACHE = "abide-v6-settled-banner";

self.addEventListener("install", (e) => {
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)),
      );
      await self.clients.claim();
    })(),
  );
});

// Push event — show notification when the streak reminder fires.
self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { title: "Abide", body: event.data ? event.data.text() : "" };
  }
  const title = data.title || "Your streak needs you";
  const body = data.body || "Open Abide and read one chapter.";
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: "/honeycombbibleapp/icon-192.png",
      badge: "/honeycombbibleapp/icon-192.png",
      tag: "streak-reminder",
      renotify: true,
      data,
    }),
  );
});

// Open the app when a notification is tapped (lands on the home screen).
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const allClients = await self.clients.matchAll({
        type: "window",
        includeUncontrolled: true,
      });
      for (const client of allClients) {
        if (client.url.includes("mikesbibleapp") && "focus" in client) {
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow("/honeycombbibleapp/");
      }
    })(),
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  const isHTML =
    req.mode === "navigate" ||
    req.destination === "document" ||
    url.pathname.endsWith("/") ||
    url.pathname.endsWith(".html");

  const isCacheableUrl = url.protocol === "http:" || url.protocol === "https:";

  if (isHTML) {
    // Network-first: always try fresh, fall back to cache when offline.
    e.respondWith(
      (async () => {
        try {
          const fresh = await fetch(req, { cache: "no-store" });
          if (isCacheableUrl && fresh && fresh.ok) {
            try {
              const cache = await caches.open(CACHE);
              await cache.put(req, fresh.clone());
            } catch {
              /* cache.put can throw on opaque/partial responses — ignore. */
            }
          }
          return fresh;
        } catch {
          const cached = await caches.match(req);
          return (
            cached ||
            new Response("Offline", {
              status: 503,
              headers: { "Content-Type": "text/plain" },
            })
          );
        }
      })(),
    );
    return;
  }

  // Cache-first for everything else (fonts, etc.) with background refresh.
  e.respondWith(
    (async () => {
      const cached = await caches.match(req);
      if (cached) {
        fetch(req)
          .then(async (fresh) => {
            if (!isCacheableUrl || !fresh || !fresh.ok) return;
            try {
              const c = await caches.open(CACHE);
              await c.put(req, fresh.clone());
            } catch {
              /* swallow */
            }
          })
          .catch(() => {});
        return cached;
      }
      try {
        const fresh = await fetch(req);
        if (isCacheableUrl && fresh && fresh.ok) {
          try {
            const cache = await caches.open(CACHE);
            await cache.put(req, fresh.clone());
          } catch {
            /* swallow */
          }
        }
        return fresh;
      } catch {
        return new Response("Offline", { status: 503 });
      }
    })(),
  );
});
