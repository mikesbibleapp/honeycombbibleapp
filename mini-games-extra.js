/* Honeycomb Mini-Games: Extra Pack
 * --------------------------------
 * Six "card-style" head-to-head minigames where Bible knowledge is NOT
 * required. Each game is deterministic from `seed` so both challenger
 * and opponent see the same board / sequence / placement.
 *
 * Lifecycle (mirrors the existing MINIGAMES registry):
 *   render(seed, container, onFinish)
 *     - seed:      integer (deterministic)
 *     - container: a live DOM node (the #mg-stage element) to fill in
 *     - onFinish:  fn(score) — higher is better (scoreLowerIsBetter:false)
 *
 * Exported via window.EXTRA_MINIGAMES = { game_id: {...} }
 * index.html will Object.assign these into the MINIGAMES dict + playMiniGame.
 */
(function () {
  "use strict";

  // ---------- Shared RNG (copied from game-content.js mulberry32) ----------
  function mulberry32(seed) {
    let t = (seed | 0) >>> 0;
    return function () {
      t = (t + 0x6d2b79f5) | 0;
      let x = Math.imul(t ^ (t >>> 15), 1 | t);
      x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
      return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
    };
  }

  function pick(rng, arr) {
    return arr[Math.floor(rng() * arr.length)];
  }
  function pickInt(rng, lo, hi) {
    return lo + Math.floor(rng() * (hi - lo + 1));
  }
  function shuffleWithRng(arr, rng) {
    const out = arr.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      const t = out[i];
      out[i] = out[j];
      out[j] = t;
    }
    return out;
  }

  // ---------- DOM helpers ----------
  function el(tag, opts) {
    const n = document.createElement(tag);
    if (!opts) return n;
    if (opts.cls) n.className = opts.cls;
    if (opts.text != null) n.textContent = opts.text;
    if (opts.html != null) n.innerHTML = opts.html;
    if (opts.style) {
      for (const k in opts.style) n.style[k] = opts.style[k];
    }
    if (opts.attrs) {
      for (const k in opts.attrs) n.setAttribute(k, opts.attrs[k]);
    }
    if (opts.on) {
      for (const k in opts.on) n.addEventListener(k, opts.on[k]);
    }
    return n;
  }

  function shell(container, title, roundText) {
    container.innerHTML = "";
    const card = el("div", { cls: "mge-card" });
    const top = el("div", { cls: "mge-top" });
    const pillRound = el("div", {
      cls: "mge-pill",
      text: roundText || "",
    });
    const pillTitle = el("div", { cls: "mge-pill mge-pill-hot", text: title });
    top.appendChild(pillRound);
    top.appendChild(pillTitle);
    card.appendChild(top);
    const body = el("div", { cls: "mge-body" });
    card.appendChild(body);
    container.appendChild(card);
    return { card, top, pillRound, pillTitle, body };
  }

  function setRound(ui, n, total) {
    ui.pillRound.textContent = "Round " + n + " of " + total;
  }

  // Tap feedback: brief scale + glow on the tapped node.
  function tapFx(node) {
    if (!node) return;
    node.classList.remove("mge-tapfx");
    // force reflow so the animation can re-trigger
    void node.offsetWidth;
    node.classList.add("mge-tapfx");
  }

  // Countdown overlay: 3 -> 2 -> 1 -> GO! then calls onGo().
  function countdown(container, onGo) {
    const wrap = el("div", { cls: "mge-countdown" });
    const big = el("div", { cls: "mge-cd-num", text: "3" });
    wrap.appendChild(big);
    container.appendChild(wrap);
    let n = 3;
    function tick() {
      big.textContent = n > 0 ? String(n) : "GO!";
      big.classList.remove("mge-cd-pop");
      void big.offsetWidth;
      big.classList.add("mge-cd-pop");
      if (n < 0) {
        wrap.parentNode && wrap.parentNode.removeChild(wrap);
        onGo();
        return;
      }
      n -= 1;
      setTimeout(tick, n < 0 ? 450 : 700);
    }
    tick();
  }

  // Reusable end-screen: large checkmark, "+X points", Continue button.
  function endScreen(container, score, emoji, onContinue) {
    container.innerHTML = "";
    const wrap = el("div", { cls: "mge-end" });
    const big = el("div", { cls: "mge-end-emoji", text: emoji || "🏆" });
    const check = el("div", { cls: "mge-end-check", text: "✓" });
    const pts = el("div", {
      cls: "mge-end-pts",
      text: "+" + Math.max(0, Math.round(score)) + " points",
    });
    const sub = el("div", {
      cls: "mge-end-sub",
      text: "Higher score wins the wager.",
    });
    const btn = el("button", {
      cls: "mge-btn mge-btn-primary",
      text: "Continue",
    });
    btn.addEventListener("click", function () {
      btn.disabled = true;
      onContinue();
    });
    wrap.appendChild(big);
    wrap.appendChild(check);
    wrap.appendChild(pts);
    wrap.appendChild(sub);
    wrap.appendChild(btn);
    container.appendChild(wrap);
  }

  // ---------- shared palette for honey jars / cells ----------
  // Five "honey" hues — high-contrast, kid-friendly.
  const HONEY_COLORS = [
    { id: "gold", bg: "#f5b300", emoji: "🟡" },
    { id: "amber", bg: "#e07a14", emoji: "🟠" },
    { id: "crimson", bg: "#c93535", emoji: "🔴" },
    { id: "violet", bg: "#7d4ac4", emoji: "🟣" },
    { id: "leaf", bg: "#3aa455", emoji: "🟢" },
  ];

  // =====================================================================
  // 1) SPEED SORT — falling honey jars, tap matching bin
  // =====================================================================
  function renderSpeedSort(seed, container, onFinish) {
    const rng = mulberry32(seed);
    const TOTAL_ROUNDS = 8;
    // Each round uses 3 of the 5 colors as visible bins; the falling jar
    // is always one of those 3. Seed drives bin selection + jar color +
    // start side.
    const rounds = [];
    for (let r = 0; r < TOTAL_ROUNDS; r++) {
      const bins = shuffleWithRng(HONEY_COLORS, rng).slice(0, 3);
      const jar = bins[Math.floor(rng() * 3)];
      const startX = pickInt(rng, 18, 82); // % across stage
      rounds.push({ bins: bins, jar: jar, startX: startX });
    }

    let roundIdx = 0;
    let correct = 0;
    let timeBonus = 0;
    let roundStart = 0;
    let activeAnim = null;
    let resolved = false;

    const ui = shell(
      container,
      "Honey Speed Sort",
      "Round 1 of " + TOTAL_ROUNDS,
    );

    const stage = el("div", { cls: "mge-ss-stage" });
    const jarEl = el("div", { cls: "mge-ss-jar", text: "🍯" });
    stage.appendChild(jarEl);
    ui.body.appendChild(stage);

    const binRow = el("div", { cls: "mge-ss-bins" });
    ui.body.appendChild(binRow);

    const status = el("div", {
      cls: "mge-status",
      text: "Tap the bin that matches the jar!",
    });
    ui.body.appendChild(status);

    function startRound() {
      if (roundIdx >= TOTAL_ROUNDS) return finish();
      setRound(ui, roundIdx + 1, TOTAL_ROUNDS);
      const r = rounds[roundIdx];
      resolved = false;
      roundStart = performance.now();

      // Render bins fresh.
      binRow.innerHTML = "";
      r.bins.forEach(function (c) {
        const b = el("button", {
          cls: "mge-ss-bin",
          style: { background: c.bg },
          attrs: { "data-id": c.id, "aria-label": c.id + " bin" },
        });
        b.appendChild(el("div", { cls: "mge-ss-bin-mouth" }));
        b.appendChild(el("div", { cls: "mge-ss-bin-label", text: "🍯" }));
        b.addEventListener("click", function () {
          if (resolved) return;
          tapFx(b);
          handlePick(c.id);
        });
        binRow.appendChild(b);
      });

      // Set jar style — tint background ring around the honey emoji.
      jarEl.style.background = r.jar.bg;
      jarEl.style.left = r.startX + "%";
      jarEl.style.top = "0px";
      jarEl.style.transform = "translate(-50%, 0)";
      jarEl.style.opacity = "1";

      // Animate falling over 2200ms.
      const stageH = Math.max(180, stage.clientHeight - 36);
      const duration = 2200;
      const t0 = performance.now();
      cancelAnimationFrame(activeAnim);
      function frame() {
        if (resolved) return;
        const dt = performance.now() - t0;
        const p = Math.min(1, dt / duration);
        jarEl.style.top = (p * stageH) | (0 + "px");
        jarEl.style.top = Math.round(p * stageH) + "px";
        if (p >= 1) {
          // timeout — counts as miss
          handlePick(null);
          return;
        }
        activeAnim = requestAnimationFrame(frame);
      }
      activeAnim = requestAnimationFrame(frame);
    }

    function handlePick(binId) {
      if (resolved) return;
      resolved = true;
      cancelAnimationFrame(activeAnim);
      const r = rounds[roundIdx];
      const elapsed = performance.now() - roundStart;
      if (binId === r.jar.id) {
        correct += 1;
        // Faster = more bonus. cap at 50 per round.
        const bonus = Math.max(0, 50 - Math.floor(elapsed / 50));
        timeBonus += bonus;
        status.textContent = "Match! +" + (100 + bonus);
        status.className = "mge-status mge-good";
        jarEl.style.opacity = "0";
      } else {
        status.textContent = binId == null ? "Too slow!" : "Wrong bin!";
        status.className = "mge-status mge-bad";
        jarEl.style.opacity = "0.35";
      }
      roundIdx += 1;
      setTimeout(startRound, 520);
    }

    function finish() {
      const score = correct * 100 + timeBonus;
      endScreen(container, score, "🍯", function () {
        onFinish(score);
      });
    }

    countdown(container.appendChild(el("div")), function () {
      // countdown removes itself; restart round
      startRound();
    });
  }

  // =====================================================================
  // 2) PATTERN REPEAT — Bee shows a sequence, kid taps it back
  // =====================================================================
  function renderPatternRepeat(seed, container, onFinish) {
    const rng = mulberry32(seed);
    // 7 hex cells in a flower pattern (1 center + 6 around).
    const CELL_COUNT = 7;
    // Pre-generate a sequence of cell indices up to length 12. Seed
    // determines the full sequence so both players see the same pattern.
    const fullSeq = [];
    for (let i = 0; i < 12; i++) fullSeq.push(Math.floor(rng() * CELL_COUNT));

    let curLen = 3;
    let highest = 0;
    let inputIdx = 0;
    let phase = "show"; // "show" | "input" | "done"

    const ui = shell(container, "Bee Pattern", "Length 3");
    const board = el("div", { cls: "mge-pr-board" });
    const status = el("div", {
      cls: "mge-status",
      text: "Watch the pattern...",
    });
    ui.body.appendChild(board);
    ui.body.appendChild(status);

    // Build 7 cells in a flower layout (center + ring of 6).
    const cells = [];
    // Position offsets in px (relative to board center). Board ~ 280px.
    const positions = [
      { x: 0, y: 0 }, // center
      { x: 0, y: -84 }, // top
      { x: 73, y: -42 }, // top-right
      { x: 73, y: 42 }, // bot-right
      { x: 0, y: 84 }, // bottom
      { x: -73, y: 42 }, // bot-left
      { x: -73, y: -42 }, // top-left
    ];
    positions.forEach(function (p, i) {
      const c = el("button", {
        cls: "mge-pr-cell",
        style: {
          left: "calc(50% + " + p.x + "px)",
          top: "calc(50% + " + p.y + "px)",
        },
        text: "🐝",
      });
      c.addEventListener("click", function () {
        if (phase !== "input") return;
        tapFx(c);
        handleInput(i);
      });
      board.appendChild(c);
      cells.push(c);
    });

    function flash(i) {
      const c = cells[i];
      c.classList.add("mge-pr-flash");
      setTimeout(function () {
        c.classList.remove("mge-pr-flash");
      }, 380);
    }

    function playSequence() {
      phase = "show";
      status.textContent = "Watch the pattern...";
      status.className = "mge-status";
      ui.pillRound.textContent = "Length " + curLen;
      const seq = fullSeq.slice(0, curLen);
      let i = 0;
      function step() {
        if (i >= seq.length) {
          phase = "input";
          inputIdx = 0;
          status.textContent = "Your turn!";
          status.className = "mge-status mge-good";
          return;
        }
        flash(seq[i]);
        i += 1;
        setTimeout(step, 520);
      }
      setTimeout(step, 400);
    }

    function handleInput(cellIdx) {
      const seq = fullSeq.slice(0, curLen);
      if (cellIdx === seq[inputIdx]) {
        inputIdx += 1;
        if (inputIdx === seq.length) {
          // round complete
          highest = curLen;
          status.textContent = "Nice! Length " + curLen + " done.";
          status.className = "mge-status mge-good";
          curLen += 1;
          if (curLen > fullSeq.length) {
            return finish();
          }
          phase = "show";
          setTimeout(playSequence, 700);
        }
      } else {
        // mistake — game over
        status.textContent = "Oops! Last good length: " + highest;
        status.className = "mge-status mge-bad";
        phase = "done";
        setTimeout(finish, 900);
      }
    }

    function finish() {
      const score = highest * 100;
      endScreen(container, score, "🐝", function () {
        onFinish(score);
      });
    }

    countdown(container.appendChild(el("div")), function () {
      playSequence();
    });
  }

  // =====================================================================
  // 3) FIND THE SHEEP — grid of sheep, spot the lost lamb
  // =====================================================================
  function renderFindSheep(seed, container, onFinish) {
    const rng = mulberry32(seed);
    const ROUNDS = 6;
    const COLS = 5;
    const ROWS = 6;
    const CELLS = COLS * ROWS;

    // Each round: pick filler animal (🐑) + lost lamb (🐏) + position.
    // To make it forgiving, the filler is always 🐑 and the odd-one is 🐏.
    const placements = [];
    for (let r = 0; r < ROUNDS; r++) {
      placements.push(Math.floor(rng() * CELLS));
    }

    let roundIdx = 0;
    let found = 0;
    let timeBonus = 0;
    let roundStart = 0;
    let locked = false;

    const ui = shell(container, "Find the Lost Sheep", "Round 1 of " + ROUNDS);
    const grid = el("div", { cls: "mge-fs-grid" });
    const status = el("div", {
      cls: "mge-status",
      text: "Tap the lamb that looks different!",
    });
    ui.body.appendChild(grid);
    ui.body.appendChild(status);

    function startRound() {
      if (roundIdx >= ROUNDS) return finish();
      setRound(ui, roundIdx + 1, ROUNDS);
      locked = false;
      roundStart = performance.now();
      const lambIdx = placements[roundIdx];
      grid.innerHTML = "";
      for (let i = 0; i < CELLS; i++) {
        const isLamb = i === lambIdx;
        const c = el("button", {
          cls: "mge-fs-cell",
          text: isLamb ? "🐏" : "🐑",
        });
        c.addEventListener("click", function () {
          if (locked) return;
          tapFx(c);
          handleTap(isLamb, c);
        });
        grid.appendChild(c);
      }
    }

    function handleTap(isLamb, cell) {
      if (isLamb) {
        locked = true;
        found += 1;
        const elapsed = performance.now() - roundStart;
        // Up to 60 bonus per round, decreasing with time.
        const bonus = Math.max(0, 60 - Math.floor(elapsed / 100));
        timeBonus += bonus;
        cell.classList.add("mge-fs-hit");
        status.textContent = "Found! +" + (100 + bonus);
        status.className = "mge-status mge-good";
        roundIdx += 1;
        setTimeout(startRound, 600);
      } else {
        // wrong tap — small penalty (shake), no end
        cell.classList.add("mge-shake");
        setTimeout(function () {
          cell.classList.remove("mge-shake");
        }, 320);
        status.textContent = "Not that one!";
        status.className = "mge-status mge-bad";
      }
    }

    function finish() {
      const score = found * 100 + timeBonus;
      endScreen(container, score, "🐏", function () {
        onFinish(score);
      });
    }

    countdown(container.appendChild(el("div")), function () {
      startRound();
    });
  }

  // =====================================================================
  // 4) HONEY MATCH 3 — 6x6 swap tiles, match 3+ of same color
  // =====================================================================
  function renderHoneyMatch3(seed, container, onFinish) {
    const rng = mulberry32(seed);
    const SIZE = 6;
    const TILE_TYPES = HONEY_COLORS; // 5 colors
    const DURATION_MS = 45000;

    // Build a board with NO initial matches (we just regen tile if it'd
    // create a 3-in-a-row at fill time).
    const board = [];
    for (let r = 0; r < SIZE; r++) {
      const row = [];
      for (let c = 0; c < SIZE; c++) {
        let attempt = 0;
        while (true) {
          const t = Math.floor(rng() * TILE_TYPES.length);
          // check no 3-in-a-row left/up at fill time
          const left2 = c >= 2 && row[c - 1] === t && row[c - 2] === t;
          const up2 = r >= 2 && board[r - 1][c] === t && board[r - 2][c] === t;
          if (!left2 && !up2) {
            row.push(t);
            break;
          }
          attempt += 1;
          if (attempt > 20) {
            row.push(t);
            break;
          }
        }
      }
      board.push(row);
    }

    let score = 0;
    let selected = null; // {r,c}
    let busy = false;
    let endsAt = 0;
    let timerId = null;
    let finished = false;

    const ui = shell(container, "Honeycomb Crush", "Time 45s");
    const grid = el("div", { cls: "mge-m3-grid" });
    const scoreLine = el("div", { cls: "mge-status", text: "Score: 0" });
    ui.body.appendChild(grid);
    ui.body.appendChild(scoreLine);

    function renderBoard() {
      grid.innerHTML = "";
      for (let r = 0; r < SIZE; r++) {
        for (let c = 0; c < SIZE; c++) {
          const t = board[r][c];
          const tile = el("button", {
            cls: "mge-m3-tile",
            style: { background: TILE_TYPES[t].bg },
            text: "🍯",
          });
          if (selected && selected.r === r && selected.c === c) {
            tile.classList.add("mge-m3-sel");
          }
          tile.addEventListener("click", function () {
            if (busy || finished) return;
            tapFx(tile);
            handleTap(r, c);
          });
          grid.appendChild(tile);
        }
      }
    }

    function handleTap(r, c) {
      if (!selected) {
        selected = { r: r, c: c };
        renderBoard();
        return;
      }
      const dr = Math.abs(selected.r - r);
      const dc = Math.abs(selected.c - c);
      if (dr + dc !== 1) {
        // not adjacent — change selection
        selected = { r: r, c: c };
        renderBoard();
        return;
      }
      // swap
      const a = selected;
      const b = { r: r, c: c };
      swap(a, b);
      const matched = findMatches();
      if (matched.length === 0) {
        // illegal — swap back, no score
        swap(a, b);
        selected = null;
        renderBoard();
        return;
      }
      selected = null;
      busy = true;
      cascade(matched);
    }

    function swap(a, b) {
      const t = board[a.r][a.c];
      board[a.r][a.c] = board[b.r][b.c];
      board[b.r][b.c] = t;
    }

    function findMatches() {
      const hits = {};
      function mark(r, c) {
        hits[r + "," + c] = true;
      }
      // horizontal runs
      for (let r = 0; r < SIZE; r++) {
        let runStart = 0;
        for (let c = 1; c <= SIZE; c++) {
          if (c === SIZE || board[r][c] !== board[r][runStart]) {
            const len = c - runStart;
            if (len >= 3) {
              for (let k = runStart; k < c; k++) mark(r, k);
            }
            runStart = c;
          }
        }
      }
      // vertical runs
      for (let c = 0; c < SIZE; c++) {
        let runStart = 0;
        for (let r = 1; r <= SIZE; r++) {
          if (r === SIZE || board[r][c] !== board[runStart][c]) {
            const len = r - runStart;
            if (len >= 3) {
              for (let k = runStart; k < r; k++) mark(k, c);
            }
            runStart = r;
          }
        }
      }
      const out = [];
      for (const key in hits) {
        const [r, c] = key.split(",").map(Number);
        out.push({ r: r, c: c });
      }
      return out;
    }

    function cascade(matched) {
      // score: 10 per tile, +5 per tile beyond the 3rd
      score += matched.length * 10 + Math.max(0, matched.length - 3) * 5;
      scoreLine.textContent = "Score: " + score;
      // mark + animate clear
      matched.forEach(function (m) {
        const idx = m.r * SIZE + m.c;
        const node = grid.children[idx];
        if (node) node.classList.add("mge-m3-pop");
      });
      setTimeout(function () {
        // null out matched
        matched.forEach(function (m) {
          board[m.r][m.c] = -1;
        });
        // gravity per column
        for (let c = 0; c < SIZE; c++) {
          const stack = [];
          for (let r = SIZE - 1; r >= 0; r--) {
            if (board[r][c] !== -1) stack.push(board[r][c]);
          }
          for (let r = SIZE - 1; r >= 0; r--) {
            if (stack.length) {
              board[r][c] = stack.shift();
            } else {
              board[r][c] = Math.floor(rng() * TILE_TYPES.length);
            }
          }
        }
        renderBoard();
        const more = findMatches();
        if (more.length) {
          cascade(more);
        } else {
          busy = false;
        }
      }, 250);
    }

    function tick() {
      const remain = Math.max(0, endsAt - performance.now());
      ui.pillRound.textContent = "Time " + (remain / 1000).toFixed(1) + "s";
      if (remain <= 0) {
        finished = true;
        clearInterval(timerId);
        endScreen(container, score, "🍯", function () {
          onFinish(score);
        });
      }
    }

    countdown(container.appendChild(el("div")), function () {
      renderBoard();
      endsAt = performance.now() + DURATION_MS;
      timerId = setInterval(tick, 100);
      tick();
    });
  }

  // =====================================================================
  // 5) REACTION TAP — one cell lights up, tap fast
  // =====================================================================
  function renderReactionTap(seed, container, onFinish) {
    const rng = mulberry32(seed);
    const ROUNDS = 10;
    const COLS = 4;
    const ROWS = 4;
    const CELLS = COLS * ROWS;

    const targets = [];
    const delays = [];
    for (let i = 0; i < ROUNDS; i++) {
      targets.push(Math.floor(rng() * CELLS));
      // delay 600-1700ms before light-up
      delays.push(600 + Math.floor(rng() * 1100));
    }

    let roundIdx = 0;
    const reactionTimes = [];
    let liveTarget = -1;
    let armedAt = 0;
    let waiting = false;
    let timeoutId = null;

    const ui = shell(container, "Quick Bee Tap", "Round 1 of " + ROUNDS);
    const grid = el("div", { cls: "mge-rt-grid" });
    const status = el("div", {
      cls: "mge-status",
      text: "Wait for the bee to land...",
    });
    ui.body.appendChild(grid);
    ui.body.appendChild(status);

    function buildGrid() {
      grid.innerHTML = "";
      for (let i = 0; i < CELLS; i++) {
        const c = el("button", { cls: "mge-rt-cell", text: "" });
        c.addEventListener("click", function () {
          handleTap(i, c);
        });
        grid.appendChild(c);
      }
    }
    buildGrid();

    function startRound() {
      if (roundIdx >= ROUNDS) return finish();
      setRound(ui, roundIdx + 1, ROUNDS);
      liveTarget = -1;
      waiting = true;
      status.textContent = "Wait...";
      status.className = "mge-status";
      // clear all cells
      for (let i = 0; i < CELLS; i++) {
        grid.children[i].classList.remove("mge-rt-live");
        grid.children[i].textContent = "";
      }
      const delay = delays[roundIdx];
      const target = targets[roundIdx];
      timeoutId = setTimeout(function () {
        liveTarget = target;
        armedAt = performance.now();
        const node = grid.children[target];
        node.classList.add("mge-rt-live");
        node.textContent = "🐝";
        status.textContent = "TAP!";
        status.className = "mge-status mge-good";
      }, delay);
    }

    function handleTap(i, node) {
      if (!waiting) return;
      tapFx(node);
      if (liveTarget < 0) {
        // tapped too early — penalty 800ms
        reactionTimes.push(800);
        status.textContent = "Too early!";
        status.className = "mge-status mge-bad";
        clearTimeout(timeoutId);
        waiting = false;
        roundIdx += 1;
        setTimeout(startRound, 550);
        return;
      }
      if (i === liveTarget) {
        const dt = performance.now() - armedAt;
        reactionTimes.push(dt);
        status.textContent = Math.round(dt) + " ms";
        status.className = "mge-status mge-good";
        waiting = false;
        roundIdx += 1;
        setTimeout(startRound, 500);
      } else {
        // wrong cell — small penalty +300ms
        const dt = performance.now() - armedAt + 300;
        reactionTimes.push(dt);
        status.textContent = "Wrong cell!";
        status.className = "mge-status mge-bad";
        waiting = false;
        roundIdx += 1;
        setTimeout(startRound, 550);
      }
    }

    function finish() {
      const avg =
        reactionTimes.reduce(function (a, b) {
          return a + b;
        }, 0) / Math.max(1, reactionTimes.length);
      const score = Math.max(0, Math.round(5000 - avg));
      endScreen(container, score, "🐝", function () {
        onFinish(score);
      });
    }

    countdown(container.appendChild(el("div")), function () {
      startRound();
    });
  }

  // =====================================================================
  // 6) SPOT THE DIFFERENCE — two 4x4 panels, one cell differs
  // =====================================================================
  function renderSpotDiff(seed, container, onFinish) {
    const rng = mulberry32(seed);
    const ROUNDS = 5;
    const COLS = 4;
    const ROWS = 4;
    const CELLS = COLS * ROWS;
    const PAIRS = ["🐝", "🌼", "🍯", "🌻", "🌷", "🦋", "🌸"];

    // Build each round: a base grid + one differing cell.
    const rounds = [];
    for (let r = 0; r < ROUNDS; r++) {
      const base = [];
      for (let i = 0; i < CELLS; i++) {
        base.push(PAIRS[Math.floor(rng() * PAIRS.length)]);
      }
      const diffCell = Math.floor(rng() * CELLS);
      // pick a different emoji for the diff cell
      let alt;
      do {
        alt = PAIRS[Math.floor(rng() * PAIRS.length)];
      } while (alt === base[diffCell]);
      rounds.push({ base: base, diffCell: diffCell, alt: alt });
    }

    let roundIdx = 0;
    let found = 0;
    let timeBonus = 0;
    let roundStart = 0;
    let locked = false;

    const ui = shell(container, "Spot the Bee", "Round 1 of " + ROUNDS);
    const board = el("div", { cls: "mge-sd-board" });
    const panelL = el("div", { cls: "mge-sd-panel" });
    const panelR = el("div", { cls: "mge-sd-panel" });
    board.appendChild(panelL);
    board.appendChild(panelR);
    const status = el("div", {
      cls: "mge-status",
      text: "Find the cell that's different in the two panels!",
    });
    ui.body.appendChild(board);
    ui.body.appendChild(status);

    function startRound() {
      if (roundIdx >= ROUNDS) return finish();
      setRound(ui, roundIdx + 1, ROUNDS);
      locked = false;
      roundStart = performance.now();
      const r = rounds[roundIdx];
      panelL.innerHTML = "";
      panelR.innerHTML = "";
      for (let i = 0; i < CELLS; i++) {
        // LEFT — always base
        const lc = el("div", { cls: "mge-sd-cell", text: r.base[i] });
        panelL.appendChild(lc);
        // RIGHT — base except at diffCell
        const isDiff = i === r.diffCell;
        const rc = el("button", {
          cls: "mge-sd-cell mge-sd-tap",
          text: isDiff ? r.alt : r.base[i],
        });
        rc.addEventListener("click", function () {
          if (locked) return;
          tapFx(rc);
          handleTap(isDiff, rc);
        });
        panelR.appendChild(rc);
      }
    }

    function handleTap(isDiff, cell) {
      if (isDiff) {
        locked = true;
        found += 1;
        const elapsed = performance.now() - roundStart;
        const bonus = Math.max(0, 80 - Math.floor(elapsed / 120));
        timeBonus += bonus;
        cell.classList.add("mge-sd-hit");
        status.textContent = "Got it! +" + (100 + bonus);
        status.className = "mge-status mge-good";
        roundIdx += 1;
        setTimeout(startRound, 650);
      } else {
        cell.classList.add("mge-shake");
        setTimeout(function () {
          cell.classList.remove("mge-shake");
        }, 320);
        status.textContent = "Look again!";
        status.className = "mge-status mge-bad";
      }
    }

    function finish() {
      const score = found * 100 + timeBonus;
      endScreen(container, score, "🐝", function () {
        onFinish(score);
      });
    }

    countdown(container.appendChild(el("div")), function () {
      startRound();
    });
  }

  // ---------- Export ----------
  window.EXTRA_MINIGAMES = window.EXTRA_MINIGAMES || {};
  window.EXTRA_MINIGAMES.speed_sort = {
    name: "Honey Speed Sort",
    sub: "Sort falling honey jars into the right bin.",
    familyUse: "Great for younger players — no reading required.",
    emoji: "🍯",
    scoreLowerIsBetter: false,
    render: renderSpeedSort,
  };
  window.EXTRA_MINIGAMES.pattern_repeat = {
    name: "Bee Pattern",
    sub: "Watch the bee pattern, then tap it back.",
    familyUse: "Pure memory — fair across all ages.",
    emoji: "🐝",
    scoreLowerIsBetter: false,
    render: renderPatternRepeat,
  };
  window.EXTRA_MINIGAMES.find_the_sheep = {
    name: "Find the Lost Sheep",
    sub: "Spot the lamb that doesn't match the flock.",
    familyUse: "Visual scanning — kids often beat adults.",
    emoji: "🐏",
    scoreLowerIsBetter: false,
    render: renderFindSheep,
  };
  window.EXTRA_MINIGAMES.honey_match3 = {
    name: "Honeycomb Crush",
    sub: "Swap honey tiles to match 3 in a row.",
    familyUse: "Classic match-3 — quick reflexes win.",
    emoji: "🍯",
    scoreLowerIsBetter: false,
    render: renderHoneyMatch3,
  };
  window.EXTRA_MINIGAMES.reaction_tap = {
    name: "Quick Bee Tap",
    sub: "Tap the bee the instant it lands.",
    familyUse: "Pure reaction time — anyone can win.",
    emoji: "🐝",
    scoreLowerIsBetter: false,
    render: renderReactionTap,
  };
  window.EXTRA_MINIGAMES.spot_the_difference = {
    name: "Spot the Bee",
    sub: "Find the one cell that's different.",
    familyUse: "Sharp eyes — great for kids.",
    emoji: "🔍",
    scoreLowerIsBetter: false,
    render: renderSpotDiff,
  };

  // ---------- Scoped CSS (prefix: .mge-) ----------
  (function injectStyles() {
    if (document.getElementById("mge-styles")) return;
    const css = `
.mge-card{
  width:100%;max-width:520px;margin:auto 0;
  background:linear-gradient(180deg,#fff8e5,#fff1cf);
  color:#3d2408;border:2px solid #f5b300;border-radius:18px;
  padding:14px 14px 16px;box-shadow:0 16px 40px rgba(61,36,8,.35);
  animation:mgeSlideUp .28s cubic-bezier(.2,1,.2,1);
}
@keyframes mgeSlideUp{from{transform:translateY(18px);opacity:0}to{transform:none;opacity:1}}
.mge-top{display:flex;justify-content:space-between;gap:10px;margin-bottom:10px}
.mge-pill{
  display:inline-flex;align-items:center;justify-content:center;
  padding:6px 12px;border-radius:999px;font-weight:700;font-size:13px;
  background:#fff;color:#3d2408;border:2px solid #f5b300;
}
.mge-pill-hot{background:#f5b300;color:#3d2408;border-color:#d99800}
.mge-body{display:flex;flex-direction:column;gap:12px;align-items:stretch}
.mge-status{
  text-align:center;font-weight:700;font-size:15px;color:#3d2408;
  background:rgba(255,255,255,.7);border-radius:10px;padding:8px 12px;
  min-height:22px;
}
.mge-good{background:#dcf6dc;color:#1d6a2c}
.mge-bad{background:#fde0e0;color:#8a1f1f}
.mge-btn{
  font:inherit;border:none;border-radius:14px;padding:14px 22px;
  font-weight:800;font-size:16px;cursor:pointer;min-height:48px;
}
.mge-btn-primary{background:#f5b300;color:#3d2408;border:2px solid #d99800}
.mge-btn-primary:hover{filter:brightness(1.05)}

/* Tap feedback */
.mge-tapfx{animation:mgeTap .22s ease-out}
@keyframes mgeTap{
  0%{transform:scale(1)}
  40%{transform:scale(1.18);box-shadow:0 0 0 6px rgba(245,179,0,.45)}
  100%{transform:scale(1)}
}
.mge-shake{animation:mgeShake .3s}
@keyframes mgeShake{
  0%,100%{transform:translateX(0)}
  25%{transform:translateX(-6px)}
  75%{transform:translateX(6px)}
}

/* Countdown */
.mge-countdown{
  position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
  background:rgba(6,16,13,.78);z-index:10;border-radius:18px;
}
.mge-cd-num{
  font-size:96px;font-weight:900;color:#f5b300;
  text-shadow:0 6px 30px rgba(245,179,0,.6);
}
.mge-cd-pop{animation:mgeCdPop .55s ease-out}
@keyframes mgeCdPop{
  0%{transform:scale(.4);opacity:0}
  50%{transform:scale(1.2);opacity:1}
  100%{transform:scale(1);opacity:1}
}

/* End screen */
.mge-end{
  text-align:center;background:linear-gradient(180deg,#fff8e5,#fff1cf);
  color:#3d2408;border:2px solid #f5b300;border-radius:18px;padding:24px 18px;
  max-width:480px;margin:auto;display:flex;flex-direction:column;align-items:center;gap:8px;
  animation:mgeSlideUp .3s cubic-bezier(.2,1,.2,1);
}
.mge-end-emoji{font-size:56px}
.mge-end-check{
  width:60px;height:60px;border-radius:50%;
  background:#3aa455;color:#fff;display:flex;align-items:center;justify-content:center;
  font-size:36px;font-weight:900;box-shadow:0 6px 18px rgba(58,164,85,.4);
}
.mge-end-pts{font-size:28px;font-weight:900;color:#3d2408;margin-top:4px}
.mge-end-sub{font-size:13px;color:#7a5a30;margin-bottom:8px}

/* 1) Speed Sort */
.mge-ss-stage{
  position:relative;height:260px;background:#3d2408;border-radius:14px;
  overflow:hidden;border:3px solid #f5b300;
}
.mge-ss-jar{
  position:absolute;width:56px;height:56px;border-radius:14px;
  display:flex;align-items:center;justify-content:center;font-size:32px;
  border:3px solid #3d2408;box-shadow:0 4px 10px rgba(0,0,0,.4);
  transition:opacity .25s;
}
.mge-ss-bins{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}
.mge-ss-bin{
  height:72px;border-radius:14px;border:3px solid #3d2408;cursor:pointer;
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  font-size:24px;min-height:48px;position:relative;
}
.mge-ss-bin-mouth{
  position:absolute;top:6px;left:14%;right:14%;height:8px;
  background:rgba(0,0,0,.3);border-radius:6px;
}
.mge-ss-bin-label{margin-top:8px}

/* 2) Pattern Repeat */
.mge-pr-board{
  position:relative;width:100%;height:280px;background:#3d2408;
  border-radius:14px;border:3px solid #f5b300;
}
.mge-pr-cell{
  position:absolute;transform:translate(-50%,-50%);
  width:64px;height:64px;border-radius:14px;border:3px solid #d99800;
  background:#f5b300;color:#3d2408;font-size:28px;cursor:pointer;
  display:flex;align-items:center;justify-content:center;
  transition:transform .15s,box-shadow .15s,background .15s;
  min-width:44px;min-height:44px;
}
.mge-pr-cell:active{transform:translate(-50%,-50%) scale(.92)}
.mge-pr-flash{
  background:#fff !important;
  box-shadow:0 0 0 8px rgba(245,179,0,.6),0 0 24px rgba(255,255,255,.9);
  transform:translate(-50%,-50%) scale(1.18);
}

/* 3) Find Sheep */
.mge-fs-grid{
  display:grid;grid-template-columns:repeat(5,1fr);gap:6px;
  background:#3d2408;padding:8px;border-radius:14px;border:3px solid #f5b300;
}
.mge-fs-cell{
  aspect-ratio:1;background:#fff8e5;border:2px solid #d99800;border-radius:10px;
  font-size:22px;display:flex;align-items:center;justify-content:center;cursor:pointer;
  min-width:44px;min-height:44px;
}
.mge-fs-hit{background:#dcf6dc !important;border-color:#3aa455 !important;animation:mgeTap .3s}

/* 4) Match 3 */
.mge-m3-grid{
  display:grid;grid-template-columns:repeat(6,1fr);gap:4px;
  background:#3d2408;padding:6px;border-radius:14px;border:3px solid #f5b300;
}
.mge-m3-tile{
  aspect-ratio:1;border:2px solid #3d2408;border-radius:10px;
  font-size:18px;display:flex;align-items:center;justify-content:center;cursor:pointer;
  min-width:44px;min-height:44px;
}
.mge-m3-sel{outline:4px solid #fff;outline-offset:-4px;transform:scale(1.05)}
.mge-m3-pop{animation:mgePop .25s ease-out forwards}
@keyframes mgePop{
  0%{transform:scale(1);opacity:1}
  100%{transform:scale(.3);opacity:0}
}

/* 5) Reaction */
.mge-rt-grid{
  display:grid;grid-template-columns:repeat(4,1fr);gap:8px;
  background:#3d2408;padding:8px;border-radius:14px;border:3px solid #f5b300;
}
.mge-rt-cell{
  aspect-ratio:1;background:#fff8e5;border:2px solid #d99800;border-radius:12px;
  font-size:32px;display:flex;align-items:center;justify-content:center;cursor:pointer;
  min-width:48px;min-height:48px;transition:background .1s;
}
.mge-rt-live{background:#f5b300 !important;box-shadow:0 0 18px rgba(245,179,0,.8)}

/* 6) Spot the Difference */
.mge-sd-board{
  display:grid;grid-template-columns:1fr 1fr;gap:8px;
  background:#3d2408;padding:8px;border-radius:14px;border:3px solid #f5b300;
}
.mge-sd-panel{display:grid;grid-template-columns:repeat(4,1fr);gap:4px}
.mge-sd-cell{
  aspect-ratio:1;background:#fff8e5;border:2px solid #d99800;border-radius:8px;
  font-size:18px;display:flex;align-items:center;justify-content:center;
  min-width:36px;min-height:36px;
}
.mge-sd-tap{cursor:pointer}
.mge-sd-hit{background:#dcf6dc !important;border-color:#3aa455 !important;animation:mgeTap .3s}
`;
    const style = document.createElement("style");
    style.id = "mge-styles";
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  })();
})();
