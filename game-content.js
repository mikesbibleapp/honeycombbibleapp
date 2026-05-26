// Honeycomb game content helpers.
// Kept separate from index.html so game rules can evolve without touching
// progress/auth code. All helpers are pure and deterministic from seed.
(function () {
  "use strict";

  const CONTEXT_SEED_BASE = 100000;

  const WHO_SAID_IT = [
    {
      quote: "I am the way, the truth, and the life.",
      speaker: "Jesus",
      books: ["John"],
    },
    { quote: "Let my people go.", speaker: "Moses", books: ["Exodus"] },
    {
      quote: "The LORD is my shepherd; I shall not want.",
      speaker: "David",
      books: ["Psalms"],
    },
    { quote: "Here am I; send me.", speaker: "Isaiah", books: ["Isaiah"] },
    { quote: "Am I my brother's keeper?", speaker: "Cain", books: ["Genesis"] },
    {
      quote: "Whither thou goest, I will go.",
      speaker: "Ruth",
      books: ["Ruth"],
    },
    {
      quote: "Prepare ye the way of the Lord.",
      speaker: "John the Baptist",
      books: ["Matthew", "Mark", "Luke", "John"],
    },
    {
      quote: "I have fought the good fight, I have finished the race.",
      speaker: "Paul",
      books: ["2 Timothy"],
    },
    {
      quote: "Why have you forsaken me?",
      speaker: "Jesus",
      books: ["Matthew", "Mark"],
    },
    {
      quote: "I am the resurrection and the life.",
      speaker: "Jesus",
      books: ["John"],
    },
    {
      quote: "Be still, and know that I am God.",
      speaker: "God",
      books: ["Psalms"],
    },
    { quote: "I am that I am.", speaker: "God", books: ["Exodus"] },
    {
      quote: "Behold, the Lamb of God.",
      speaker: "John the Baptist",
      books: ["John"],
    },
    {
      quote: "Father, forgive them; for they know not what they do.",
      speaker: "Jesus",
      books: ["Luke"],
    },
    { quote: "It is finished.", speaker: "Jesus", books: ["John"] },
    {
      quote: "I will arise and go to my father.",
      speaker: "Prodigal Son",
      books: ["Luke"],
    },
    {
      quote: "Faith without works is dead.",
      speaker: "James",
      books: ["James"],
    },
    {
      quote: "Stand still, and see the salvation of the LORD.",
      speaker: "Moses",
      books: ["Exodus"],
    },
    {
      quote: "Choose you this day whom ye will serve.",
      speaker: "Joshua",
      books: ["Joshua"],
    },
    {
      quote: "Speak, LORD, for thy servant heareth.",
      speaker: "Samuel",
      books: ["1 Samuel"],
    },
    {
      quote: "I am a man of unclean lips.",
      speaker: "Isaiah",
      books: ["Isaiah"],
    },
    {
      quote: "By their fruit you will recognize them.",
      speaker: "Jesus",
      books: ["Matthew"],
    },
    {
      quote: "Love your enemies.",
      speaker: "Jesus",
      books: ["Matthew", "Luke"],
    },
    {
      quote: "Truly this man was the Son of God.",
      speaker: "Roman Centurion",
      books: ["Mark"],
    },
    {
      quote: "I can do all things through Christ who strengthens me.",
      speaker: "Paul",
      books: ["Philippians"],
    },
    {
      quote: "Blessed are the poor in spirit.",
      speaker: "Jesus",
      books: ["Matthew"],
    },
    {
      quote: "Have I not commanded you? Be strong and courageous.",
      speaker: "God",
      books: ["Joshua"],
    },
    {
      quote: "If God is for us, who can be against us?",
      speaker: "Paul",
      books: ["Romans"],
    },
    {
      quote: "We do not live by bread alone.",
      speaker: "Jesus",
      books: ["Matthew", "Luke"],
    },
    {
      quote: "Vanity of vanities; all is vanity.",
      speaker: "Solomon",
      books: ["Ecclesiastes"],
    },
    {
      quote: "Behold, I make all things new.",
      speaker: "Jesus",
      books: ["Revelation"],
    },
    {
      quote: "Today salvation has come to this house.",
      speaker: "Jesus",
      books: ["Luke"],
    },
    {
      quote: "Get behind me, Satan!",
      speaker: "Jesus",
      books: ["Matthew", "Mark"],
    },
    {
      quote: "I am with you always, even to the end of the age.",
      speaker: "Jesus",
      books: ["Matthew"],
    },
    { quote: "How long, O LORD?", speaker: "David", books: ["Psalms"] },
    { quote: "What is truth?", speaker: "Pilate", books: ["John"] },
    {
      quote: "Where two or three are gathered, I am there.",
      speaker: "Jesus",
      books: ["Matthew"],
    },
    {
      quote: "My grace is sufficient for you.",
      speaker: "God",
      books: ["2 Corinthians"],
    },
    {
      quote: "Even so, come, Lord Jesus.",
      speaker: "John",
      books: ["Revelation"],
    },
    {
      quote: "Naked I came from my mother's womb, and naked shall I return.",
      speaker: "Job",
      books: ["Job"],
    },
  ];

  function mulberry32(seed) {
    let t = seed >>> 0;
    return function () {
      t = (t + 0x6d2b79f5) | 0;
      let x = Math.imul(t ^ (t >>> 15), 1 | t);
      x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
      return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
    };
  }

  function shuffle(arr, rng) {
    const out = arr.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      const tmp = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }

  function makeContextSeed(planIdx) {
    const idx = Math.max(0, Math.min(9999, planIdx || 0));
    const salt = Math.floor(Math.random() * CONTEXT_SEED_BASE);
    return idx * CONTEXT_SEED_BASE + salt;
  }

  function seedParts(seed, planLength) {
    // caller must ensure planIdx < planLength; otherwise the n % planLength
    // fallback silently remaps to an unrelated plan index.
    const n = Math.max(0, Math.floor(Number(seed) || 0));
    const encodedIdx = Math.floor(n / CONTEXT_SEED_BASE);
    const planIdx =
      encodedIdx > 0 && encodedIdx < planLength
        ? encodedIdx
        : n % Math.max(1, planLength || 1);
    return { planIdx, salt: n % CONTEXT_SEED_BASE };
  }

  function bookMap(bible) {
    const m = {};
    (bible.books || []).forEach((b) => (m[b.name] = b));
    return m;
  }

  function versePool(bible, plan, seed) {
    const rng = mulberry32(seed);
    const byBook = bookMap(bible);
    const parts = seedParts(seed, plan.length);
    const dayStart = Math.max(0, Math.floor(parts.planIdx / 4) * 4);
    const contextPlan = [];
    for (
      let i = Math.max(0, dayStart - 4);
      i < Math.min(plan.length, dayStart + 8);
      i++
    ) {
      contextPlan.push(plan[i]);
    }

    const context = [];
    contextPlan.forEach(([bk, ch]) => {
      const book = byBook[bk];
      const chapter = book && book.chapters[ch - 1];
      if (!chapter) return;
      chapter.forEach((row) => {
        const text = row[1];
        if (
          typeof text === "string" &&
          text.length >= 45 &&
          text.length <= 220
        ) {
          context.push({ book: bk, ch, vn: row[0], text });
        }
      });
    });

    const all = [];
    (bible.books || []).forEach((book) => {
      book.chapters.forEach((chapter, cIdx) => {
        chapter.forEach((row) => {
          const text = row[1];
          if (
            typeof text === "string" &&
            text.length >= 45 &&
            text.length <= 220
          ) {
            all.push({ book: book.name, ch: cIdx + 1, vn: row[0], text });
          }
        });
      });
    });

    return {
      rng,
      planIdx: parts.planIdx,
      context: shuffle(context, rng),
      all: shuffle(all, rng),
      contextBooks: [...new Set(contextPlan.map((p) => p[0]))],
    };
  }

  function splitVerse(v) {
    const words = v.text.split(/\s+/).filter(Boolean);
    if (words.length < 9) return null;
    const splitAt = Math.max(4, Math.floor(words.length * 0.48));
    const first = words.slice(0, splitAt).join(" ");
    const second = words.slice(splitAt).join(" ");
    if (second.length < 18) return null;
    return { first, second };
  }

  function fillWrongEndings(target, candidates, rng) {
    const wrong = [];
    candidates.forEach((v) => {
      if (wrong.length >= 3) return;
      if (v.text === target.text) return;
      const s = splitVerse(v);
      if (!s || s.second === target.second || wrong.includes(s.second)) return;
      wrong.push(s.second);
    });
    return shuffle(wrong, rng).slice(0, 3);
  }

  function finishVerseQuestions(bible, plan, seed, rounds) {
    const pool = versePool(bible, plan, seed);
    const primary =
      pool.context.length >= rounds
        ? pool.context
        : pool.context.concat(pool.all);
    const questions = [];
    const used = new Set();
    primary.forEach((v) => {
      if (questions.length >= rounds) return;
      const split = splitVerse(v);
      if (!split) return;
      const id = `${v.book}|${v.ch}|${v.vn}`;
      if (used.has(id)) return;
      used.add(id);
      const wrong = fillWrongEndings(
        Object.assign({}, v, split),
        pool.context.concat(pool.all),
        pool.rng,
      );
      if (wrong.length < 3) return;
      const options = shuffle(wrong.concat([split.second]), pool.rng);
      questions.push({
        ref: `${v.book} ${v.ch}:${v.vn}`,
        prompt: split.first + " ...",
        options,
        answer: options.indexOf(split.second),
      });
    });
    return questions;
  }

  function matchBookQuestions(bible, plan, seed, rounds) {
    const pool = versePool(bible, plan, seed);
    const allBooks = (bible.books || []).map((b) => b.name);
    const preferred =
      pool.context.length >= rounds
        ? pool.context
        : pool.context.concat(pool.all);
    const questions = [];
    const used = new Set();
    preferred.forEach((v) => {
      if (questions.length >= rounds) return;
      const id = `${v.book}|${v.ch}|${v.vn}`;
      if (used.has(id)) return;
      used.add(id);
      const distractorBase = shuffle(
        pool.contextBooks.concat(allBooks),
        pool.rng,
      );
      const wrong = [];
      distractorBase.forEach((b) => {
        if (wrong.length < 3 && b !== v.book && !wrong.includes(b))
          wrong.push(b);
      });
      if (wrong.length < 3) return;
      const options = shuffle(wrong.concat([v.book]), pool.rng);
      questions.push({
        ref: `${v.book} ${v.ch}:${v.vn}`,
        prompt: v.text,
        options,
        answer: options.indexOf(v.book),
      });
    });
    return questions;
  }

  function whoSaidQuestions(bible, plan, seed, rounds) {
    const pool = versePool(bible, plan, seed);
    const speakers = [...new Set(WHO_SAID_IT.map((q) => q.speaker))];
    const related = WHO_SAID_IT.filter((q) =>
      (q.books || []).some((b) => pool.contextBooks.includes(b)),
    );
    const source = shuffle(related.concat(WHO_SAID_IT), pool.rng);
    const questions = [];
    const used = new Set();
    source.forEach((q) => {
      if (questions.length >= rounds) return;
      const id = q.quote + "|" + q.speaker;
      if (used.has(id)) return;
      used.add(id);
      const wrong = [];
      shuffle(speakers, pool.rng).forEach((s) => {
        if (wrong.length < 3 && s !== q.speaker && !wrong.includes(s))
          wrong.push(s);
      });
      if (wrong.length < 3) return;
      const options = shuffle(wrong.concat([q.speaker]), pool.rng);
      questions.push({
        ref: (q.books && q.books[0]) || "Who said it?",
        prompt: `"${q.quote}"`,
        options,
        answer: options.indexOf(q.speaker),
      });
    });
    return questions;
  }

  function buildQuestions(opts) {
    const rounds = opts.rounds || 10;
    if (opts.game === "finish_verse") {
      return finishVerseQuestions(opts.bible, opts.plan, opts.seed, rounds);
    }
    if (opts.game === "match_book") {
      return matchBookQuestions(opts.bible, opts.plan, opts.seed, rounds);
    }
    if (opts.game === "who_said") {
      return whoSaidQuestions(opts.bible, opts.plan, opts.seed, rounds);
    }
    return [];
  }

  window.HoneycombGameContent = {
    CONTEXT_SEED_BASE,
    WHO_SAID_IT,
    makeContextSeed,
    seedParts,
    buildQuestions,
  };
})();
