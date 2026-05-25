export const PREMIUM_APP_CONTRACTS_VERSION = "2026.05.25-premium-contracts-v1";

export const PREMIUM_THEME_CONTRACTS = Object.freeze([
  {
    id: "trail_adventure",
    name: "Trail Adventure",
    intent: "main progression, map movement, and daily quest confidence",
    palette: {
      canvas: "#fff8e6",
      surface: "#ffffff",
      primary: "#2f7a98",
      accent: "#d89542",
      reward: "#e2a84c",
      ink: "#1f2933",
    },
    typography: {
      display: "Plus Jakarta Sans",
      body: "Plus Jakarta Sans",
      scripture: "Newsreader",
    },
    motion: {
      level: "playful",
      allowed: ["progress-count", "map-pan", "character-float", "reward-pop"],
    },
    assetMood: ["storybook map", "warm path lighting", "clear quest landmarks"],
  },
  {
    id: "cup_competition",
    name: "Cup Competition",
    intent: "family race energy without implying reading progress can be bought",
    palette: {
      canvas: "#f7fbff",
      surface: "#ffffff",
      primary: "#315f7c",
      accent: "#d95f45",
      reward: "#f2b544",
      ink: "#1d2530",
    },
    typography: {
      display: "Plus Jakarta Sans",
      body: "Plus Jakarta Sans",
      scripture: "Newsreader",
    },
    motion: {
      level: "arcade",
      allowed: ["car-advance", "jackpot-pulse", "rank-change", "mission-claim"],
    },
    assetMood: ["race track", "team energy", "honey jackpot"],
  },
  {
    id: "reader_focus",
    name: "Reader Focus",
    intent: "quiet, high-trust Scripture reading with low visual load",
    palette: {
      canvas: "#fffdf6",
      surface: "#ffffff",
      primary: "#476e7c",
      accent: "#8f6d3d",
      reward: "#d5a72f",
      ink: "#1c2430",
    },
    typography: {
      display: "Plus Jakarta Sans",
      body: "Plus Jakarta Sans",
      scripture: "Newsreader",
    },
    motion: {
      level: "calm",
      allowed: ["scroll-progress", "highlight-confirm", "chapter-complete"],
    },
    assetMood: ["clean parchment", "soft lamp glow", "readable Scripture"],
  },
  {
    id: "reward_cabinet",
    name: "Reward Cabinet",
    intent: "achievement clarity, collectibles, and earned celebration",
    palette: {
      canvas: "#fff7ee",
      surface: "#ffffff",
      primary: "#7f5a2e",
      accent: "#476e7c",
      reward: "#d5a72f",
      ink: "#24211d",
    },
    typography: {
      display: "Plus Jakarta Sans",
      body: "Plus Jakarta Sans",
      scripture: "Newsreader",
    },
    motion: {
      level: "celebratory",
      allowed: ["chest-open", "badge-shine", "garage-preview", "claim-pop"],
    },
    assetMood: ["polished cabinet", "storybook trophies", "earned badges"],
  },
  {
    id: "settings_clarity",
    name: "Settings Clarity",
    intent: "calm account, family, theme, and safety controls",
    palette: {
      canvas: "#f8faf7",
      surface: "#ffffff",
      primary: "#3f6f5a",
      accent: "#5f6fa3",
      reward: "#c99b3d",
      ink: "#1f2a25",
    },
    typography: {
      display: "Plus Jakarta Sans",
      body: "Plus Jakarta Sans",
      scripture: "Newsreader",
    },
    motion: {
      level: "minimal",
      allowed: ["toggle", "save-confirm", "panel-expand"],
    },
    assetMood: ["plain controls", "family-safe account tools", "low distraction"],
  },
]);

export const PREMIUM_ECONOMY_CATEGORIES = Object.freeze([
  {
    id: "progress",
    name: "Real Progress",
    unit: "completed chapters",
    sourceOfTruth: "Bible reading state",
    canBePurchased: false,
    protects: ["Bible Trail position", "chapter completion", "book completion"],
  },
  {
    id: "honey",
    name: "Honey",
    unit: "honey",
    sourceOfTruth: "earned and spent balance",
    canBePurchased: false,
    protects: ["reward pacing", "family wagering", "shop spending"],
  },
  {
    id: "protection",
    name: "Protection",
    unit: "streak freeze",
    sourceOfTruth: "inventory",
    canBePurchased: true,
    protects: ["streak continuity", "family race momentum"],
  },
  {
    id: "competition",
    name: "Competition",
    unit: "Cup points and wagers",
    sourceOfTruth: "family room race state",
    canBePurchased: false,
    protects: ["family-game fairness", "daily jackpot rules"],
  },
  {
    id: "cosmetic",
    name: "Cosmetic",
    unit: "outfits, rides, trails, aura",
    sourceOfTruth: "owned and equipped cosmetics",
    canBePurchased: true,
    protects: ["identity", "reward expression", "non-progress advantages"],
  },
  {
    id: "gifting",
    name: "Gifting",
    unit: "sent honey",
    sourceOfTruth: "family and friend transfer records",
    canBePurchased: true,
    protects: ["social recovery", "rematches", "generosity loop"],
  },
]);

export const PREMIUM_ECONOMY_LOOPS = Object.freeze([
  {
    id: "read_move_earn",
    name: "Read, Move, Earn",
    categoryIds: ["progress", "honey"],
    screenIds: ["bible_trail", "reader", "rewards"],
    steps: [
      "Open the next assigned chapter",
      "Complete real reading progress",
      "Move the Bible Trail position",
      "Award honey and eligible rewards",
    ],
    guardrails: [
      "Only completed reading moves Bible Trail progress",
      "Game boosts never mark chapters complete",
    ],
  },
  {
    id: "family_cup_daily_race",
    name: "Family Cup Daily Race",
    categoryIds: ["competition", "honey", "protection"],
    screenIds: ["family_cup", "bible_trail", "shop"],
    steps: [
      "Read to add race points",
      "Use eligible Cup actions for position only",
      "Settle the daily jackpot after the cutoff",
      "Feed results back into the weekly pot",
    ],
    guardrails: [
      "Cup power-ups can move race position only",
      "Cup settlement cannot rewrite reading history",
    ],
  },
  {
    id: "collect_customize_show",
    name: "Collect, Customize, Show",
    categoryIds: ["cosmetic", "honey"],
    screenIds: ["rewards", "shop", "bible_trail", "family_cup"],
    steps: [
      "Earn or buy a cosmetic",
      "Equip it in the character garage",
      "Show it on the Trail and Cup surfaces",
      "Return to reading or racing for more unlocks",
    ],
    guardrails: [
      "Cosmetics do not change Scripture progress",
      "Equipped visuals must have starter fallbacks",
    ],
  },
  {
    id: "highlight_return_read",
    name: "Highlight, Return, Read",
    categoryIds: ["progress"],
    screenIds: ["reader", "highlights", "bible_trail"],
    steps: [
      "Highlight or save a Scripture moment",
      "Review saved highlights",
      "Jump back into the reader context",
      "Continue the next Trail chapter",
    ],
    guardrails: [
      "Highlights reference Scripture locations",
      "Reviewing highlights does not grant chapter completion",
    ],
  },
  {
    id: "shop_spend_recover",
    name: "Shop, Spend, Recover",
    categoryIds: ["honey", "protection", "competition", "gifting", "cosmetic"],
    screenIds: ["shop", "family_cup", "settings"],
    steps: [
      "Open the Honey Shop with a signed-in balance",
      "Spend honey on protection, Cup tools, cosmetics, or gifts",
      "Apply inventory or social effects",
      "Return to reading to refill the economy",
    ],
    guardrails: [
      "Honey purchases should be reversible only through explicit product rules",
      "Shop tools must disclose when they affect Cup position instead of progress",
    ],
  },
]);

export const PREMIUM_SCREEN_CONTRACTS = Object.freeze([
  {
    id: "bible_trail",
    name: "Bible Trail",
    legacyAnchors: ["today view", "renderToday", "adventure-home", "economy-dock"],
    themeId: "trail_adventure",
    primaryJob: "Show the next real reading quest and the visible journey through Scripture.",
    stateScopes: ["plan cursor", "completed chapters", "honey balance", "family room summary"],
    economyCategoryIds: ["progress", "honey", "competition", "cosmetic"],
    economyLoopIds: ["read_move_earn", "family_cup_daily_race", "collect_customize_show"],
    surfaceContracts: [
      "Daily quest launch",
      "Bible region map",
      "Economy dock",
      "Garage preview",
      "Family Cup preview",
    ],
    behaviorBoundaries: [
      "Do not mark reading complete outside the Reader completion flow",
      "Do not hide the next readable chapter behind cosmetics or Cup state",
    ],
  },
  {
    id: "family_cup",
    name: "Family Cup",
    legacyAnchors: ["renderFamilyRoomCard", "renderFamilyRoomModal", "family room RPCs"],
    themeId: "cup_competition",
    primaryJob: "Turn family reading into a daily and weekly race with clear pots, ranks, and safe power-ups.",
    stateScopes: ["family room", "race points", "daily jackpot", "weekly pot", "family goals"],
    economyCategoryIds: ["competition", "honey", "protection", "gifting"],
    economyLoopIds: ["family_cup_daily_race", "shop_spend_recover"],
    surfaceContracts: [
      "Race track",
      "Daily jackpot banner",
      "Mission claims",
      "Power-up dock",
      "Family standings",
      "Goal wagers",
    ],
    behaviorBoundaries: [
      "Power-ups affect race points and position only",
      "Daily settlement must be explicit or scheduled after the published cutoff",
    ],
  },
  {
    id: "reader",
    name: "Reader",
    legacyAnchors: ["reader view", "reader-inner", "reader progress", "chapter completion"],
    themeId: "reader_focus",
    primaryJob: "Provide readable Scripture, contextual tools, and trustworthy completion moments.",
    stateScopes: ["current reference", "scroll progress", "highlights", "completion reward preview"],
    economyCategoryIds: ["progress", "honey"],
    economyLoopIds: ["read_move_earn", "highlight_return_read"],
    surfaceContracts: [
      "Chapter header",
      "Scripture body",
      "Highlight tools",
      "Reader progress",
      "Completion reward preview",
    ],
    behaviorBoundaries: [
      "Scripture text remains the visual priority",
      "Completion rewards appear only after the configured reading condition is met",
    ],
  },
  {
    id: "rewards",
    name: "Rewards",
    legacyAnchors: ["reward chest", "badges", "garage", "leaderboard rewards"],
    themeId: "reward_cabinet",
    primaryJob: "Make earned progress, badges, characters, and claimable rewards feel collectible and legible.",
    stateScopes: ["badges", "owned cosmetics", "unlocked characters", "claimable rewards"],
    economyCategoryIds: ["progress", "honey", "cosmetic"],
    economyLoopIds: ["read_move_earn", "collect_customize_show"],
    surfaceContracts: [
      "Reward chest",
      "Badge cabinet",
      "Character garage",
      "Claim states",
      "Locked previews",
    ],
    behaviorBoundaries: [
      "Locked rewards must explain their earning path",
      "Claimed rewards must not double-award after refresh",
    ],
  },
  {
    id: "shop",
    name: "Shop",
    legacyAnchors: ["openHoneyShop", "SHOP_ITEMS", "buyShopItem"],
    themeId: "reward_cabinet",
    primaryJob: "Convert earned honey into clear, bounded tools, cosmetics, gifts, and protection.",
    stateScopes: ["honey balance", "inventory", "owned cosmetics", "family room eligibility"],
    economyCategoryIds: ["honey", "protection", "competition", "cosmetic", "gifting"],
    economyLoopIds: ["shop_spend_recover", "collect_customize_show", "family_cup_daily_race"],
    surfaceContracts: [
      "Balance header",
      "Item list",
      "Affordability state",
      "Purchase confirmation",
      "Gift amount picker",
    ],
    behaviorBoundaries: [
      "Shop copy must distinguish progress from position boosts",
      "Unauthenticated users see sign-in gating before purchases",
    ],
  },
  {
    id: "highlights",
    name: "Highlights",
    legacyAnchors: ["highlights view", "highlight cards", "highlight colors"],
    themeId: "reader_focus",
    primaryJob: "Let readers revisit marked Scripture and re-enter the reading journey.",
    stateScopes: ["saved highlights", "highlight colors", "Scripture references"],
    economyCategoryIds: ["progress"],
    economyLoopIds: ["highlight_return_read"],
    surfaceContracts: [
      "Highlight list",
      "Reference labels",
      "Color filters",
      "Reader return action",
      "Empty state",
    ],
    behaviorBoundaries: [
      "Highlight review cannot grant honey by itself",
      "Stored references must remain stable across theme changes",
    ],
  },
  {
    id: "settings",
    name: "Settings",
    legacyAnchors: ["settings view", "theme toggle", "account controls", "family state"],
    themeId: "settings_clarity",
    primaryJob: "Expose account, theme, notification, family, and data controls without game ambiguity.",
    stateScopes: ["settings", "theme", "auth state", "family membership", "local progress"],
    economyCategoryIds: ["honey", "gifting", "protection"],
    economyLoopIds: ["shop_spend_recover"],
    surfaceContracts: [
      "Theme controls",
      "Account status",
      "Family room controls",
      "Notification settings",
      "Data management",
    ],
    behaviorBoundaries: [
      "Settings toggles should not mutate reading progress",
      "Destructive data actions require explicit confirmation",
    ],
  },
]);

export function getPremiumScreenContract(screenId) {
  return PREMIUM_SCREEN_CONTRACTS.find((screen) => screen.id === screenId) || null;
}

export function getPremiumThemeContract(themeId) {
  return PREMIUM_THEME_CONTRACTS.find((theme) => theme.id === themeId) || null;
}

export function getPremiumEconomyCategory(categoryId) {
  return PREMIUM_ECONOMY_CATEGORIES.find((category) => category.id === categoryId) || null;
}

export function listPremiumEconomyLoopsForScreen(screenId) {
  return PREMIUM_ECONOMY_LOOPS.filter((loop) => loop.screenIds.includes(screenId));
}

export function listPremiumScreensByEconomyCategory(categoryId) {
  return PREMIUM_SCREEN_CONTRACTS.filter((screen) =>
    screen.economyCategoryIds.includes(categoryId),
  );
}
