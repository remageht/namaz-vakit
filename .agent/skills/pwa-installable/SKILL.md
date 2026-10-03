---
name: pwa-installable
description: Progressive Web App installation guidelines, web app manifest, cache-first service worker, and mobile installation prompts.
---

# PWA Installable Skill

## Web App Manifest (`manifest.json`)
Requirements for full PWA installability across Chromium, Edge, iOS Safari:
```json
{
  "name": "Намаз",
  "short_name": "Намаз",
  "description": "Время намаза, обратный отсчёт, уведомления, компас Киблы и уроки 5 намазов",
  "start_url": "./index.html",
  "display": "standalone",
  "background_color": "#06281f",
  "theme_color": "#06281f",
  "orientation": "portrait",
  "icons": [
    {
      "src": "icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

## Service Worker (`sw.js`)
Cache-first strategy for app shell assets:
- Cache key with versioning (e.g., `namaz-pwa-v1`)
- Precache app shell: `['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png']`
- Cache-first with network fallback for static files
- Network-first or bypass for dynamic API endpoints like Aladhan API

## Installation Instructions
- **Android Chrome**: Tap `⋮` (menu) -> "Установить приложение" (Install app) or "Добавить на главный экран"
- **iPhone Safari**: Tap Share button `⬆` -> "На экран «Домой»" (Add to Home Screen)
- **Desktop Chrome / Edge**: Click install icon `⬇` in address bar
