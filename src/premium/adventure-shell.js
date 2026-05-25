export const HONEYCOMB_ADVENTURE_SHELL_VERSION = "2026.05.25-premium-adventure-v1";

export {
  ADVENTURE_ART_DIRECTION,
  ADVENTURE_ASSET_ROOT,
  ADVENTURE_WORLD_REGIONS,
  EXISTING_ADVENTURE_ASSETS,
  PREMIUM_ADVENTURE_DATA_VERSION,
  PREMIUM_ASSET_PLAN,
  PREMIUM_CHARACTER_ARCHETYPES,
  PREMIUM_MOUNTS_AND_VEHICLES,
  PREMIUM_OUTFITS,
  PREMIUM_TRAILS,
  buildPremiumCharacterLoadout,
  getAdventureRegionForBook,
  getPremiumCharacter,
  listPremiumAssetRequests,
  listPremiumCharactersByRegion,
  listPremiumOutfitOptions,
} from "./adventure-world-data.js";

import { ADVENTURE_WORLD_REGIONS } from "./adventure-world-data.js";

export const ADVENTURE_REGIONS = ADVENTURE_WORLD_REGIONS.map(({ id, name, tone, books }) => ({
  id,
  name,
  tone,
  books,
}));

export function installAdventureShell() {
  document.documentElement.dataset.shell = "premium-adventure";
  document.documentElement.dataset.shellVersion = HONEYCOMB_ADVENTURE_SHELL_VERSION;
}

installAdventureShell();
