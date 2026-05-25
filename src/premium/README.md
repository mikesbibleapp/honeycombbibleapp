# Honeycomb Premium Adventure Shell

This folder is the migration point for the premium Biblical adventure rebuild.

Current production is still the static GitHub Pages PWA in `index.html`, so this
shell starts as a tiny module that marks the app with a version and exports the
region model used by the new design direction. Future slices should move screen
rendering, shared state adapters, and design tokens here without changing the
existing Supabase/local progress contract.

Guardrails:
- Do not rewrite Bible progress, completed chapters, streaks, honey, family room
  membership, or leaderboard data.
- Game power-ups may affect race/game position, never actual reading progress.
- Keep the PWA deploy path compatible with GitHub Pages.
