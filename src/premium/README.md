# Honeycomb Premium Adventure Shell

This folder is the migration point for the premium Biblical adventure rebuild.

Current production is still the static GitHub Pages PWA in `index.html`, so this
shell starts as a tiny module that marks the app with a version and exports the
region model used by the new design direction. Future slices should move screen
rendering, shared state adapters, and design tokens here without changing the
existing Supabase/local progress contract.

## Data modules

- `adventure-shell.js` remains the browser-loaded entry point from `index.html`.
  It preserves the existing shell marker behavior and re-exports premium
  adventure data for future screens.
- `adventure-world-data.js` is data-only: professional character archetypes,
  outfits, mounts/vehicles, trails, regions, current asset references, and an
  asset production backlog. It has no DOM side effects and can be imported by
  tests, build tooling, or future UI slices.

Guardrails:
- Do not rewrite Bible progress, completed chapters, streaks, honey, family room
  membership, or leaderboard data.
- Game power-ups may affect race/game position, never actual reading progress.
- Keep the PWA deploy path compatible with GitHub Pages.
