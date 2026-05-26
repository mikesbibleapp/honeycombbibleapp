export const PREMIUM_ADVENTURE_DATA_VERSION = "2026.05.25-premium-world-v1";

export const ADVENTURE_ASSET_ROOT = "assets/adventure";

export const ADVENTURE_ART_DIRECTION = Object.freeze({
  style: "storybook adventure with warm cinematic lighting",
  ageRange: "family-friendly, readable for early elementary children",
  fidelity: "polished 2D characters with clear silhouettes and modest details",
  avoid: [
    "photoreal gore",
    "weapon-forward poses",
    "caricatured ethnic features",
    "modern fantasy armor",
    "text baked into character art",
  ],
});

export const ADVENTURE_WORLD_REGIONS = Object.freeze([
  {
    id: "creation",
    name: "Creation",
    tone: "garden",
    era: "Beginnings",
    books: ["Genesis"],
    palette: ["#3f8f63", "#87c66f", "#f3d17c", "#5fb6c8"],
    landmarks: ["Eden garden paths", "newly made hills", "riverside groves"],
    ambientAssetKeys: ["map_background", "olive_leaf_trail", "sunrise_glow"],
  },
  {
    id: "patriarchs",
    name: "Patriarchs",
    tone: "desert",
    era: "Promises",
    books: ["Genesis"],
    palette: ["#c58a45", "#e0b56f", "#8c6f4d", "#4d8b8a"],
    landmarks: ["tent camps", "well courtyards", "starry desert ridges"],
    ambientAssetKeys: ["sand_trail", "starfield_trail", "camel_mount"],
  },
  {
    id: "exodus",
    name: "Exodus",
    tone: "sea",
    era: "Deliverance",
    books: ["Exodus", "Leviticus", "Numbers", "Deuteronomy"],
    palette: ["#2f7a98", "#77c6d4", "#d7b16d", "#efefe6"],
    landmarks: ["Red Sea crossing", "wilderness camp", "tabernacle courts"],
    ambientAssetKeys: ["sea_parting_trail", "manna_spark_trail", "reed_basket"],
  },
  {
    id: "kingdom",
    name: "Kingdom",
    tone: "gold",
    era: "Kings and worship",
    books: [
      "Joshua",
      "Judges",
      "Ruth",
      "1 Samuel",
      "2 Samuel",
      "1 Kings",
      "2 Kings",
      "1 Chronicles",
      "2 Chronicles",
    ],
    palette: ["#7f5a2e", "#d5a72f", "#456c7b", "#9f3f45"],
    landmarks: ["Jerusalem gates", "palace training yard", "temple approach"],
    ambientAssetKeys: ["temple_trophy", "royal_banner_trail", "harp_notes"],
  },
  {
    id: "exile",
    name: "Exile",
    tone: "night",
    era: "Wisdom and prophets",
    books: [
      "Ezra",
      "Nehemiah",
      "Esther",
      "Job",
      "Psalms",
      "Proverbs",
      "Ecclesiastes",
      "Song of Solomon",
      "Isaiah",
      "Jeremiah",
      "Lamentations",
      "Ezekiel",
      "Daniel",
    ],
    palette: ["#32435f", "#7469a8", "#d9b45e", "#b9c6d6"],
    landmarks: ["city walls", "royal courts", "quiet writing rooms"],
    ambientAssetKeys: ["scroll_light_trail", "lamp_glow", "city_wall_gate"],
  },
  {
    id: "gospel",
    name: "Gospel",
    tone: "sunrise",
    era: "Jesus' ministry",
    books: ["Matthew", "Mark", "Luke", "John"],
    palette: ["#d89542", "#f4ce84", "#5fa4a2", "#6a8f4e"],
    landmarks: ["Galilee shoreline", "hillside paths", "village courtyards"],
    ambientAssetKeys: ["fishing_boat", "olive_leaf_trail", "sunrise_glow"],
  },
  {
    id: "church",
    name: "Church",
    tone: "fire",
    era: "Early church",
    books: [
      "Acts",
      "Romans",
      "1 Corinthians",
      "2 Corinthians",
      "Galatians",
      "Ephesians",
      "Philippians",
      "Colossians",
      "1 Thessalonians",
      "2 Thessalonians",
      "1 Timothy",
      "2 Timothy",
      "Titus",
      "Philemon",
      "Hebrews",
      "James",
      "1 Peter",
      "2 Peter",
      "1 John",
      "2 John",
      "3 John",
      "Jude",
      "Revelation",
    ],
    palette: ["#a64f3c", "#e2a84c", "#476e7c", "#d8d5c5"],
    landmarks: ["Roman roads", "harbor docks", "house church rooms"],
    ambientAssetKeys: [
      "scroll_light_trail",
      "merchant_cart",
      "harbor_lanterns",
    ],
  },
]);

export const PREMIUM_CHARACTER_ARCHETYPES = Object.freeze([
  {
    id: "noah",
    displayName: "Noah",
    role: "faithful builder",
    homeRegionId: "creation",
    storyArcBooks: ["Genesis"],
    defaultOutfitId: "linen_workwear",
    outfitIds: ["linen_workwear", "patriarch_traveler", "builder_apron"],
    mountOrVehicleIds: ["ark_deck", "donkey"],
    trailIds: ["olive_leaf_trail", "rainbow_mist_trail"],
    portraitAssetKey: "character_noah_builder",
  },
  {
    id: "moses",
    displayName: "Moses",
    role: "wilderness leader",
    homeRegionId: "exodus",
    storyArcBooks: ["Exodus", "Leviticus", "Numbers", "Deuteronomy"],
    defaultOutfitId: "prophet_mantle",
    outfitIds: ["prophet_mantle", "desert_traveler", "tabernacle_guide"],
    mountOrVehicleIds: ["reed_basket", "donkey"],
    trailIds: ["sea_parting_trail", "manna_spark_trail"],
    portraitAssetKey: "character_moses_staff",
  },
  {
    id: "david",
    displayName: "David",
    role: "shepherd king",
    homeRegionId: "kingdom",
    storyArcBooks: ["1 Samuel", "2 Samuel", "Psalms"],
    defaultOutfitId: "shepherd_cloak",
    outfitIds: ["shepherd_cloak", "royal_robe", "harp_bearer"],
    mountOrVehicleIds: ["donkey", "royal_chariot"],
    trailIds: ["harp_notes_trail", "royal_banner_trail"],
    portraitAssetKey: "character_david_harp",
  },
  {
    id: "esther",
    displayName: "Esther",
    role: "brave queen",
    homeRegionId: "exile",
    storyArcBooks: ["Esther"],
    defaultOutfitId: "royal_robe",
    outfitIds: ["royal_robe", "scribe_robes", "festival_cloak"],
    mountOrVehicleIds: ["royal_chariot", "merchant_cart"],
    trailIds: ["scroll_light_trail", "royal_banner_trail"],
    portraitAssetKey: "character_esther_courage",
  },
  {
    id: "mary_magdalene",
    displayName: "Mary Magdalene",
    role: "first witness",
    homeRegionId: "gospel",
    storyArcBooks: ["Matthew", "Mark", "Luke", "John"],
    defaultOutfitId: "galilee_traveler",
    outfitIds: ["galilee_traveler", "linen_workwear", "festival_cloak"],
    mountOrVehicleIds: ["donkey", "fishing_boat"],
    trailIds: ["sunrise_glow_trail", "olive_leaf_trail"],
    portraitAssetKey: "character_mary_magdalene_sunrise",
  },
  {
    id: "paul",
    displayName: "Paul",
    role: "missionary teacher",
    homeRegionId: "church",
    storyArcBooks: [
      "Acts",
      "Romans",
      "1 Corinthians",
      "Galatians",
      "Ephesians",
      "Philippians",
    ],
    defaultOutfitId: "roman_travel_cloak",
    outfitIds: ["roman_travel_cloak", "scribe_robes", "tentmaker_apron"],
    mountOrVehicleIds: ["merchant_cart", "fishing_boat"],
    trailIds: ["scroll_light_trail", "harbor_lantern_trail"],
    portraitAssetKey: "character_paul_scroll",
  },
]);

export const PREMIUM_OUTFITS = Object.freeze([
  {
    id: "linen_workwear",
    name: "Linen Workwear",
    silhouette: "simple tunic, rope belt, practical sandals",
    regionIds: ["creation", "gospel"],
    assetKey: "outfit_linen_workwear",
  },
  {
    id: "builder_apron",
    name: "Builder Apron",
    silhouette: "layered apron, rolled sleeves, tool pouch",
    regionIds: ["creation", "patriarchs"],
    assetKey: "outfit_builder_apron",
  },
  {
    id: "patriarch_traveler",
    name: "Patriarch Traveler",
    silhouette: "weathered cloak, head wrap, travel satchel",
    regionIds: ["patriarchs"],
    assetKey: "outfit_patriarch_traveler",
  },
  {
    id: "desert_traveler",
    name: "Desert Traveler",
    silhouette: "sun cloak, staff loop, dust-worn sandals",
    regionIds: ["exodus", "patriarchs"],
    assetKey: "outfit_desert_traveler",
  },
  {
    id: "prophet_mantle",
    name: "Prophet Mantle",
    silhouette: "long mantle, staff pose, strong readable folds",
    regionIds: ["exodus", "exile"],
    assetKey: "outfit_prophet_mantle",
  },
  {
    id: "tabernacle_guide",
    name: "Tabernacle Guide",
    silhouette: "cream robe, blue sash, polished bronze accents",
    regionIds: ["exodus"],
    assetKey: "outfit_tabernacle_guide",
  },
  {
    id: "shepherd_cloak",
    name: "Shepherd Cloak",
    silhouette: "short cloak, sling pouch, soft wool texture",
    regionIds: ["kingdom"],
    assetKey: "outfit_shepherd_cloak",
  },
  {
    id: "harp_bearer",
    name: "Harp Bearer",
    silhouette: "musician wrap, small harp, warm gold trim",
    regionIds: ["kingdom"],
    assetKey: "outfit_harp_bearer",
  },
  {
    id: "royal_robe",
    name: "Royal Robe",
    silhouette: "layered robe, modest jewelry, ceremonial sash",
    regionIds: ["kingdom", "exile"],
    assetKey: "outfit_royal_robe",
  },
  {
    id: "scribe_robes",
    name: "Scribe Robes",
    silhouette: "ink satchel, scroll case, soft layered robe",
    regionIds: ["exile", "church"],
    assetKey: "outfit_scribe_robes",
  },
  {
    id: "festival_cloak",
    name: "Festival Cloak",
    silhouette: "bright cloak, simple embroidery, celebratory sash",
    regionIds: ["exile", "gospel"],
    assetKey: "outfit_festival_cloak",
  },
  {
    id: "galilee_traveler",
    name: "Galilee Traveler",
    silhouette: "shoreline cloak, woven bag, practical sandals",
    regionIds: ["gospel"],
    assetKey: "outfit_galilee_traveler",
  },
  {
    id: "roman_travel_cloak",
    name: "Roman Road Cloak",
    silhouette: "travel cloak, scroll satchel, sturdy sandals",
    regionIds: ["church"],
    assetKey: "outfit_roman_travel_cloak",
  },
  {
    id: "tentmaker_apron",
    name: "Tentmaker Apron",
    silhouette: "work apron, folded canvas, small stitching tools",
    regionIds: ["church"],
    assetKey: "outfit_tentmaker_apron",
  },
]);

export const PREMIUM_MOUNTS_AND_VEHICLES = Object.freeze([
  {
    id: "donkey",
    name: "Gentle Donkey",
    type: "mount",
    regionIds: ["patriarchs", "exodus", "kingdom", "gospel"],
    assetKey: "mount_donkey",
  },
  {
    id: "camel",
    name: "Desert Camel",
    type: "mount",
    regionIds: ["patriarchs"],
    assetKey: "mount_camel",
  },
  {
    id: "reed_basket",
    name: "Reed Basket",
    type: "vehicle",
    regionIds: ["exodus"],
    assetKey: "vehicle_reed_basket",
  },
  {
    id: "ark_deck",
    name: "Ark Deck",
    type: "vehicle",
    regionIds: ["creation"],
    assetKey: "vehicle_ark_deck",
  },
  {
    id: "royal_chariot",
    name: "Royal Chariot",
    type: "vehicle",
    regionIds: ["kingdom", "exile"],
    assetKey: "vehicle_royal_chariot",
  },
  {
    id: "fishing_boat",
    name: "Galilee Fishing Boat",
    type: "vehicle",
    regionIds: ["gospel", "church"],
    assetKey: "vehicle_fishing_boat",
  },
  {
    id: "merchant_cart",
    name: "Merchant Cart",
    type: "vehicle",
    regionIds: ["exile", "church"],
    assetKey: "vehicle_merchant_cart",
  },
]);

export const PREMIUM_TRAILS = Object.freeze([
  {
    id: "olive_leaf_trail",
    name: "Olive Leaf Trail",
    motion: "soft leaf drift",
    regionIds: ["creation", "gospel"],
    assetKey: "trail_olive_leaf",
  },
  {
    id: "rainbow_mist_trail",
    name: "Rainbow Mist",
    motion: "subtle prismatic arc",
    regionIds: ["creation"],
    assetKey: "trail_rainbow_mist",
  },
  {
    id: "sand_trail",
    name: "Desert Sand",
    motion: "low dust curl",
    regionIds: ["patriarchs"],
    assetKey: "trail_sand",
  },
  {
    id: "starfield_trail",
    name: "Promise Stars",
    motion: "small twinkling points",
    regionIds: ["patriarchs", "exile"],
    assetKey: "trail_starfield",
  },
  {
    id: "sea_parting_trail",
    name: "Parted Sea Wake",
    motion: "blue wave shimmer",
    regionIds: ["exodus"],
    assetKey: "trail_sea_parting",
  },
  {
    id: "manna_spark_trail",
    name: "Manna Spark",
    motion: "warm falling sparkles",
    regionIds: ["exodus"],
    assetKey: "trail_manna_spark",
  },
  {
    id: "harp_notes_trail",
    name: "Harp Notes",
    motion: "gold music-note glints",
    regionIds: ["kingdom"],
    assetKey: "trail_harp_notes",
  },
  {
    id: "royal_banner_trail",
    name: "Royal Banner",
    motion: "small pennant sways",
    regionIds: ["kingdom", "exile"],
    assetKey: "trail_royal_banner",
  },
  {
    id: "scroll_light_trail",
    name: "Scroll Light",
    motion: "paper flecks and lamp glow",
    regionIds: ["exile", "church"],
    assetKey: "trail_scroll_light",
  },
  {
    id: "sunrise_glow_trail",
    name: "Sunrise Glow",
    motion: "warm edge glow",
    regionIds: ["gospel"],
    assetKey: "trail_sunrise_glow",
  },
  {
    id: "harbor_lantern_trail",
    name: "Harbor Lanterns",
    motion: "gentle amber bobbing lights",
    regionIds: ["church"],
    assetKey: "trail_harbor_lantern",
  },
]);

export const EXISTING_ADVENTURE_ASSETS = Object.freeze({
  map_background: `${ADVENTURE_ASSET_ROOT}/map-background.svg`,
  bible_world_map_ai: `${ADVENTURE_ASSET_ROOT}/bible-world-map-ai.png`,
  character_showcase_ai: `${ADVENTURE_ASSET_ROOT}/character-showcase-ai.png`,
  reward_chest: `${ADVENTURE_ASSET_ROOT}/reward-chest.svg`,
  temple_trophy: `${ADVENTURE_ASSET_ROOT}/temple-trophy.svg`,
});

export const PREMIUM_ASSET_PLAN = Object.freeze({
  characterPortraits: PREMIUM_CHARACTER_ARCHETYPES.map((character) => ({
    assetKey: character.portraitAssetKey,
    suggestedPath: `${ADVENTURE_ASSET_ROOT}/characters/${character.id}.webp`,
    subject: `${character.displayName}, ${character.role}`,
  })),
  outfits: PREMIUM_OUTFITS.map((outfit) => ({
    assetKey: outfit.assetKey,
    suggestedPath: `${ADVENTURE_ASSET_ROOT}/outfits/${outfit.id}.webp`,
    subject: outfit.silhouette,
  })),
  mountsAndVehicles: PREMIUM_MOUNTS_AND_VEHICLES.map((item) => ({
    assetKey: item.assetKey,
    suggestedPath: `${ADVENTURE_ASSET_ROOT}/rides/${item.id}.webp`,
    subject: `${item.name} ${item.type}`,
  })),
  trails: PREMIUM_TRAILS.map((trail) => ({
    assetKey: trail.assetKey,
    suggestedPath: `${ADVENTURE_ASSET_ROOT}/trails/${trail.id}.webp`,
    subject: trail.motion,
  })),
});

export function getAdventureRegionForBook(bookName, chapter) {
  // Genesis spans two regions: Creation (chapters 1-11) and Patriarchs (12-50).
  // When a chapter is provided we can disambiguate; otherwise fall back to the
  // first matching region for backward compatibility.
  if (bookName === "Genesis" && typeof chapter === "number" && chapter >= 12) {
    return (
      ADVENTURE_WORLD_REGIONS.find((region) => region.id === "patriarchs") ||
      null
    );
  }
  return (
    ADVENTURE_WORLD_REGIONS.find((region) => region.books.includes(bookName)) ||
    null
  );
}

export function getPremiumCharacter(characterId) {
  return (
    PREMIUM_CHARACTER_ARCHETYPES.find(
      (character) => character.id === characterId,
    ) || null
  );
}

export function listPremiumCharactersByRegion(regionId) {
  return PREMIUM_CHARACTER_ARCHETYPES.filter(
    (character) => character.homeRegionId === regionId,
  );
}

export function listPremiumOutfitOptions(characterId) {
  const character = getPremiumCharacter(characterId);
  if (!character) return [];

  return character.outfitIds
    .map((outfitId) => PREMIUM_OUTFITS.find((outfit) => outfit.id === outfitId))
    .filter(Boolean);
}

export function buildPremiumCharacterLoadout(characterId, options = {}) {
  const character = getPremiumCharacter(characterId);
  if (!character) return null;

  const outfitId = character.outfitIds.includes(options.outfitId)
    ? options.outfitId
    : character.defaultOutfitId;
  const mountOrVehicleId = character.mountOrVehicleIds.includes(
    options.mountOrVehicleId,
  )
    ? options.mountOrVehicleId
    : character.mountOrVehicleIds[0];
  const trailId = character.trailIds.includes(options.trailId)
    ? options.trailId
    : character.trailIds[0];

  return {
    character,
    region:
      ADVENTURE_WORLD_REGIONS.find(
        (region) => region.id === character.homeRegionId,
      ) || null,
    outfit: PREMIUM_OUTFITS.find((outfit) => outfit.id === outfitId) || null,
    mountOrVehicle:
      PREMIUM_MOUNTS_AND_VEHICLES.find(
        (item) => item.id === mountOrVehicleId,
      ) || null,
    trail: PREMIUM_TRAILS.find((trail) => trail.id === trailId) || null,
  };
}

export function listPremiumAssetRequests() {
  return [
    ...PREMIUM_ASSET_PLAN.characterPortraits,
    ...PREMIUM_ASSET_PLAN.outfits,
    ...PREMIUM_ASSET_PLAN.mountsAndVehicles,
    ...PREMIUM_ASSET_PLAN.trails,
  ];
}
