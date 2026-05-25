const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const code = fs.readFileSync(path.join(__dirname, "..", "game-content.js"), "utf8");
const sandbox = { window: {} };
vm.createContext(sandbox);
vm.runInContext(code, sandbox);

const GameContent = sandbox.window.HoneycombGameContent;

const BIBLE = {
  books: [
    {
      name: "Genesis",
      chapters: [
        [
          [1, "In the beginning God created the heavens and the earth and the earth was formless and empty."],
          [2, "God said let there be light and there was light shining over the waters."],
          [3, "God saw that the light was good and separated the light from the darkness."],
          [4, "God called the light day and the darkness he called night and there was evening."],
        ],
        [
          [1, "Thus the heavens and the earth were finished and all their vast array was complete."],
          [2, "God rested from all his work which he had made and blessed the seventh day."],
          [3, "The man and his wife were in the garden and heard the voice of the Lord God."],
          [4, "The serpent was more subtle than any animal of the field which the Lord God had made."],
        ],
      ],
    },
    {
      name: "Exodus",
      chapters: [
        [
          [1, "Moses saw the bush burning with fire and the bush was not consumed before his eyes."],
          [2, "God called to him out of the bush and said Moses Moses and he said here I am."],
          [3, "The Lord said I have surely seen the affliction of my people who are in Egypt."],
          [4, "Come now therefore and I will send you to Pharaoh that you may bring my people out."],
        ],
      ],
    },
    {
      name: "John",
      chapters: [
        [
          [1, "In the beginning was the Word and the Word was with God and the Word was God."],
          [2, "The light shines in the darkness and the darkness has not overcome it."],
          [3, "Behold the Lamb of God who takes away the sin of the world."],
          [4, "Jesus said I am the way and the truth and the life and no one comes to the Father except through me."],
        ],
      ],
    },
    {
      name: "Psalms",
      chapters: [
        [
          [1, "The Lord is my shepherd I shall not want and he makes me lie down in green pastures."],
          [2, "He restores my soul and leads me in paths of righteousness for his name sake."],
          [3, "Even though I walk through the valley of the shadow of death I will fear no evil."],
          [4, "Surely goodness and mercy shall follow me all the days of my life forever."],
        ],
      ],
    },
  ],
};

const PLAN = [
  ["Genesis", 1],
  ["Genesis", 2],
  ["Exodus", 1],
  ["John", 1],
  ["Psalms", 1],
];

function assertQuestions(game, seed) {
  const qs = GameContent.buildQuestions({
    game,
    seed,
    bible: BIBLE,
    plan: PLAN,
    rounds: game === "who_said" ? 4 : 3,
  });
  assert.ok(qs.length > 0, `${game} should generate questions`);
  qs.forEach((q) => {
    assert.ok(q.prompt && q.ref, `${game} question should have prompt/ref`);
    assert.strictEqual(q.options.length, 4, `${game} should have 4 options`);
    assert.ok(q.answer >= 0 && q.answer < q.options.length, `${game} answer index valid`);
  });
  return qs;
}

const seed = GameContent.CONTEXT_SEED_BASE * 3 + 42;
const finishA = assertQuestions("finish_verse", seed);
const finishB = assertQuestions("finish_verse", seed);
assert.deepStrictEqual(finishA, finishB, "same seed should generate same finish-verse questions");

assertQuestions("match_book", seed);
assertQuestions("who_said", seed);

const contextualSeed = GameContent.makeContextSeed(2);
const parts = GameContent.seedParts(contextualSeed, PLAN.length);
assert.strictEqual(parts.planIdx, 2, "context seed should preserve plan index");

console.log("game-content tests passed");
