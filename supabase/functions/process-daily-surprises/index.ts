import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import webpush from "npm:web-push@3.6.7";
import { SURPRISE_VERSE_PLAN } from "./verse-map.generated.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-honeycomb-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") || "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") || "";
const VAPID_SUBJECT =
  Deno.env.get("VAPID_SUBJECT") || "mailto:mikebell@airafitness.com";
const CRON_SECRET = Deno.env.get("CRON_SECRET") || "";

const SURPRISE_TYPES = [
  "honey_storm",
  "flash_race",
  "mystery_box",
  "showdown",
  "crown_hunt",
  "wildcard_day",
  "swarm",
] as const;

type SurpriseType = (typeof SURPRISE_TYPES)[number];

type FamilyRoom = {
  id: string;
  owner_id: string;
  name?: string | null;
};

type Member = {
  user_id: string;
  joined_at: string;
  last_seen_at?: string | null;
  display_name?: string;
  state?: Record<string, unknown>;
  total_chapters?: number;
};

const SHORT_WINDOWS_MINUTES: Record<SurpriseType, number | null> = {
  honey_storm: 30,
  flash_race: 60,
  mystery_box: null,
  showdown: 60,
  crown_hunt: null,
  wildcard_day: null,
  swarm: null,
};

const COPY: Record<
  SurpriseType,
  { icon: string; title: string; body: string; modal: string }
> = {
  honey_storm: {
    icon: "🍯",
    title: "Honey Storm!",
    body: "For the next 30 minutes, real chapters earn 3x honey.",
    modal: "Read during the storm and your chapter honey triples.",
  },
  flash_race: {
    icon: "⚡",
    title: "Flash Race!",
    body: "First family member to finish 2 chapters in the next hour wins 200 honey.",
    modal: "First to 2 real chapters wins the flash prize.",
  },
  mystery_box: {
    icon: "🎁",
    title: "Mystery Box Day!",
    body: "Your first chapter today opens a mystery prize.",
    modal: "Finish one chapter today to reveal your mystery prize.",
  },
  showdown: {
    icon: "🕊️",
    title: "Showdown!",
    body: "Two family members have one hour to read first and win honey.",
    modal: "Two readers are in a one-chapter showdown.",
  },
  crown_hunt: {
    icon: "👑",
    title: "Crown Hunt!",
    body: "A hidden verse is somewhere in today's family reading.",
    modal: "Read carefully. The first person to pass the hidden verse wins.",
  },
  wildcard_day: {
    icon: "🎲",
    title: "Wildcard Day!",
    body: "Everyone who reads at least 1 chapter today gets a surprise cosmetic.",
    modal: "Read one real chapter today and claim a free cosmetic.",
  },
  swarm: {
    icon: "🐝",
    title: "Swarm!",
    body: "First family member to read 3 chapters in any hour gets a 24h 2x honey buff.",
    modal: "Read 3 chapters inside one hour to bank a 2x honey buff.",
  },
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

function addUtcDays(dateStr: string, days: number) {
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d + days, 0, 0, 0));
  return isoDate(date);
}

async function sha256Bytes(input: string): Promise<Uint8Array> {
  const encoded = new TextEncoder().encode(input);
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoded));
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = await sha256Bytes(input);
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function u32(bytes: Uint8Array, offset: number) {
  return (
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3]
  ) >>> 0;
}

function avoidRepeatType(
  pickedType: SurpriseType,
  pickedIndex: number,
  yesterdayType?: SurpriseType | null,
): SurpriseType {
  return pickedType === yesterdayType
    ? SURPRISE_TYPES[(pickedIndex + 1) % SURPRISE_TYPES.length]
    : pickedType;
}

async function rollDailySurprise(
  familyRoomId: string,
  utcDate: string,
  ownerOffsetMinutes: number,
  yesterdayType?: SurpriseType | null,
) {
  const seed = `${familyRoomId}:${utcDate}:daily-surprise-v1`;
  const bytes = await sha256Bytes(seed);
  const pickedIndex = u32(bytes, 0) % SURPRISE_TYPES.length;
  const surpriseType = avoidRepeatType(
    SURPRISE_TYPES[pickedIndex],
    pickedIndex,
    yesterdayType,
  );
  const durationMinutes = SHORT_WINDOWS_MINUTES[surpriseType];
  const wakingMinutes = 13 * 60;
  const latestStartOffset = wakingMinutes - (durationMinutes ?? 0);
  const startOffsetFrom8am = u32(bytes, 4) % (latestStartOffset + 1);
  const localStartMinute = 8 * 60 + startOffsetFrom8am;
  const [year, month, day] = utcDate.split("-").map(Number);
  const localMidnightUtc = Date.UTC(year, month - 1, day, 0, 0, 0);
  const startAtMs =
    localMidnightUtc + (localStartMinute + ownerOffsetMinutes) * 60_000;
  const endAtMs = durationMinutes
    ? startAtMs + durationMinutes * 60_000
    : localMidnightUtc + (23 * 60 + 59 + ownerOffsetMinutes) * 60_000 + 59_000;
  return {
    seed,
    surpriseType,
    startAt: new Date(startAtMs).toISOString(),
    endAt: new Date(endAtMs).toISOString(),
  };
}

async function ownerOffsetMinutes(admin: ReturnType<typeof createClient>, room: FamilyRoom) {
  const { data } = await admin
    .from("user_progress")
    .select("tz_offset_minutes")
    .eq("user_id", room.owner_id)
    .maybeSingle();
  const raw = Number(data && data.tz_offset_minutes);
  return Number.isFinite(raw) ? raw : 300;
}

async function loadMembers(
  admin: ReturnType<typeof createClient>,
  roomId: string,
): Promise<Member[]> {
  const { data: members, error: memberError } = await admin
    .from("family_room_members")
    .select("user_id, joined_at, last_seen_at")
    .eq("room_id", roomId)
    .eq("active", true);
  if (memberError || !members?.length) return [];

  const ids = (members as Array<{ user_id: string }>).map((m) => m.user_id);
  const [{ data: profiles }, { data: progressRows }] = await Promise.all([
    admin.from("profiles").select("id, display_name").in("id", ids),
    admin
      .from("user_progress")
      .select("user_id, state, total_chapters")
      .in("user_id", ids),
  ]);
  const profileById = new Map(
    ((profiles || []) as Array<{ id: string; display_name?: string }>).map((p) => [
      p.id,
      p,
    ]),
  );
  const progressById = new Map(
    ((progressRows || []) as Array<{
      user_id: string;
      state?: Record<string, unknown>;
      total_chapters?: number;
    }>).map((p) => [p.user_id, p]),
  );

  return (members as Array<{
    user_id: string;
    joined_at: string;
    last_seen_at?: string | null;
  }>).map((m) => {
    const profile = profileById.get(m.user_id);
    const progress = progressById.get(m.user_id);
    return {
      user_id: m.user_id,
      joined_at: m.joined_at,
      last_seen_at: m.last_seen_at,
      display_name: profile?.display_name || "Reader",
      state: (progress?.state || {}) as Record<string, unknown>,
      total_chapters: Number(progress?.total_chapters || 0),
    };
  });
}

function eligibleMembers(members: Member[], now: Date) {
  const minJoinMs = now.getTime() - 24 * 60 * 60 * 1000;
  return members.filter((m) => new Date(m.joined_at).getTime() <= minJoinMs);
}

function activeMembers(members: Member[], now: Date) {
  const minSeenMs = now.getTime() - 48 * 60 * 60 * 1000;
  return eligibleMembers(members, now).filter(
    (m) => m.last_seen_at && new Date(m.last_seen_at).getTime() >= minSeenMs,
  );
}

function userTodayPlanCandidates(member: Member) {
  const stateCursor = Number(member.state?.cursor);
  const cursor = Number.isFinite(stateCursor)
    ? stateCursor
    : Number(member.total_chapters || 0);
  const start = Math.max(0, Math.floor(cursor / 4) * 4);
  return SURPRISE_VERSE_PLAN.slice(start, start + 4).filter(
    (row) => row && row.verseCount > 0,
  );
}

async function buildPayload(
  surpriseType: SurpriseType,
  room: FamilyRoom,
  utcDate: string,
  seed: string,
  members: Member[],
  now: Date,
): Promise<Record<string, any>> {
  const base: Record<string, unknown> = {
    seed,
    icon: COPY[surpriseType].icon,
    title: COPY[surpriseType].title,
    body: COPY[surpriseType].modal,
    utc_date: utcDate,
  };
  const eligible = eligibleMembers(members, now);

  if (!eligible.length) {
    return {
      ...base,
      skipped: true,
      skip_reason: "no eligible members older than 24 hours",
    };
  }

  if (surpriseType === "showdown") {
    const active = activeMembers(members, now);
    if (active.length < 2) {
      return {
        ...base,
        skipped: true,
        skip_reason: "not enough active members for showdown",
      };
    }
    const ranked = await Promise.all(
      active.map(async (member) => ({
        member,
        hash: await sha256Hex(`${seed}:showdown:${member.user_id}`),
      })),
    );
    ranked.sort((a, b) => a.hash.localeCompare(b.hash));
    const pair = ranked.slice(0, 2).map((row) => row.member);
    return {
      ...base,
      participants: pair.map((m) => m.user_id),
      participant_names: Object.fromEntries(
        pair.map((m) => [m.user_id, m.display_name || "Reader"]),
      ),
      prize_honey: 150,
    };
  }

  if (surpriseType === "crown_hunt") {
    const candidates = eligible.flatMap((member) => userTodayPlanCandidates(member));
    if (!candidates.length) {
      return {
        ...base,
        skipped: true,
        skip_reason: "no verse candidates found",
      };
    }
    const bytes = await sha256Bytes(`${seed}:crown`);
    const picked = candidates[u32(bytes, 0) % candidates.length];
    const verse = 1 + (u32(bytes, 4) % Math.max(1, picked.verseCount));
    return {
      ...base,
      crown_verse_ref: {
        book: picked.book,
        chapter: picked.chapter,
        verse,
      },
      public_hint: "A hidden verse is in today's family reading.",
      prize_honey: 300,
    };
  }

  if (surpriseType === "honey_storm") return { ...base, multiplier: 3 };
  if (surpriseType === "flash_race") {
    return { ...base, target_chapters: 2, prize_honey: 200 };
  }
  if (surpriseType === "mystery_box") {
    return {
      ...base,
      prize_pool: {
        honey_50: 40,
        honey_200: 30,
        honey_500: 10,
        cosmetic: 10,
        honey_boost_2x_24h: 7,
        steal_100: 3,
      },
    };
  }
  if (surpriseType === "wildcard_day") {
    return { ...base, reward: "random_unowned_cosmetic" };
  }
  return { ...base, target_chapters: 3, span_minutes: 60, reward: "2x_honey_24h" };
}

async function pushToMembers(
  admin: ReturnType<typeof createClient>,
  members: Member[],
  type: SurpriseType,
  payload: Record<string, unknown>,
) {
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY || !members.length) {
    return { sent: 0, failed: 0, stale: 0, skipped: true };
  }
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
  const ids = members.map((m) => m.user_id);
  const { data: subscriptions, error } = await admin
    .from("push_subscriptions")
    .select("id, user_id, endpoint, p256dh, auth")
    .in("user_id", ids);
  if (error || !subscriptions?.length) {
    return { sent: 0, failed: 0, stale: 0, skipped: true };
  }

  const byId = new Map(members.map((m) => [m.user_id, m]));
  let sent = 0;
  let failed = 0;
  const staleIds: string[] = [];

  await Promise.all(
    (subscriptions as Array<{
      id: string;
      user_id: string;
      endpoint: string;
      p256dh: string;
      auth: string;
    }>).map(async (sub) => {
      const member = byId.get(sub.user_id);
      let title = COPY[type].title;
      let body = COPY[type].body;
      if (type === "showdown") {
        const participants = Array.isArray(payload.participants)
          ? payload.participants.map(String)
          : [];
        const names = (payload.participant_names || {}) as Record<string, string>;
        if (participants.includes(sub.user_id)) {
          const opponentId = participants.find((id) => id !== sub.user_id) || "";
          const opponentName = names[opponentId] || "someone";
          title = `Showdown with ${opponentName}!`;
          body = "First to finish 1 chapter in the next hour wins honey.";
        } else {
          const pair = participants.map((id) => names[id] || "Reader").join(" vs ");
          body = `${pair || "Two readers"} are in a one-hour Showdown.`;
        }
      } else if (member?.display_name && type === "mystery_box") {
        body = `${member.display_name}, your first chapter today opens a mystery prize.`;
      }

      const notification = JSON.stringify({
        title,
        body,
        url: "https://mikesbibleapp.github.io/honeycombbibleapp/?view=cup&surprise=1",
        tag: `honeycomb-surprise-${type}`,
        type: `daily-surprise-${type}`,
      });
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          notification,
        );
        sent += 1;
      } catch (pushError) {
        failed += 1;
        const statusCode = Number((pushError as { statusCode?: number }).statusCode);
        if (statusCode === 404 || statusCode === 410) staleIds.push(sub.id);
        console.warn("daily surprise push failed", statusCode || pushError);
      }
    }),
  );

  if (staleIds.length) {
    await admin.from("push_subscriptions").delete().in("id", staleIds);
  }
  return { sent, failed, stale: staleIds.length };
}

async function maybeNotifyRow(
  admin: ReturnType<typeof createClient>,
  row: Record<string, unknown>,
  room: FamilyRoom,
  now: Date,
) {
  const startAt = new Date(String(row.start_at));
  const endAt = new Date(String(row.end_at));
  const payload = (row.payload || {}) as Record<string, unknown>;
  if (startAt > now || endAt <= now || payload.notified_at || payload.skipped) {
    return { notified: false, push: null };
  }
  const members = eligibleMembers(await loadMembers(admin, room.id), now);
  const push = await pushToMembers(
    admin,
    members,
    String(row.surprise_type) as SurpriseType,
    payload,
  );
  await admin
    .from("family_surprises")
    .update({
      payload: {
        ...payload,
        notified_at: now.toISOString(),
        push,
      },
      updated_at: now.toISOString(),
    })
    .eq("id", row.id);
  return { notified: true, push };
}

async function createDueSurpriseForRoom(
  admin: ReturnType<typeof createClient>,
  room: FamilyRoom,
  now: Date,
) {
  const utcDate = isoDate(now);

  const { data: todayRows } = await admin
    .from("family_surprises")
    .select("*")
    .eq("family_room_id", room.id)
    .eq("surprise_date", utcDate)
    .limit(1);
  if (todayRows?.[0]) {
    const notify = await maybeNotifyRow(admin, todayRows[0], room, now);
    return { row: todayRows[0], created: false, ...notify };
  }

  const { data: activeRows } = await admin
    .from("family_surprises")
    .select("id")
    .eq("family_room_id", room.id)
    .is("resolved_at", null)
    .gt("end_at", now.toISOString())
    .limit(1);
  if (activeRows?.length) return { skipped: "active surprise already exists" };

  const { data: yesterdayRows } = await admin
    .from("family_surprises")
    .select("surprise_type, payload")
    .eq("family_room_id", room.id)
    .eq("surprise_date", addUtcDays(utcDate, -1))
    .limit(1);
  const yesterday = yesterdayRows?.[0];
  const yesterdayPayload = (yesterday?.payload || {}) as Record<string, unknown>;
  const yesterdayType =
    yesterday && !yesterdayPayload.skipped
      ? (String(yesterday.surprise_type) as SurpriseType)
      : null;

  const offset = await ownerOffsetMinutes(admin, room);
  const roll = await rollDailySurprise(room.id, utcDate, offset, yesterdayType);
  const startAt = new Date(roll.startAt);
  const endAt = new Date(roll.endAt);
  if (startAt > now) return { due: false, starts_at: roll.startAt };
  if (endAt <= now) return { due: false, expired: true };

  const members = await loadMembers(admin, room.id);
  const payload = await buildPayload(
    roll.surpriseType,
    room,
    utcDate,
    roll.seed,
    members,
    now,
  );

  const resolvedAt = payload.skipped ? now.toISOString() : null;
  const { data: inserted, error } = await admin
    .from("family_surprises")
    .insert({
      family_room_id: room.id,
      surprise_type: roll.surpriseType,
      surprise_date: utcDate,
      start_at: roll.startAt,
      end_at: roll.endAt,
      payload,
      resolved_at: resolvedAt,
    })
    .select("*")
    .maybeSingle();

  if (error) {
    console.warn("daily surprise insert failed", error);
    return { error: error.message };
  }
  if (!inserted || payload.skipped) {
    return { row: inserted, created: !!inserted, skipped: payload.skip_reason || true };
  }

  const eligible = eligibleMembers(members, now);
  const push = await pushToMembers(admin, eligible, roll.surpriseType, payload);
  const updatedPayload = {
    ...payload,
    notified_at: now.toISOString(),
    push,
  };
  await admin
    .from("family_surprises")
    .update({ payload: updatedPayload, updated_at: now.toISOString() })
    .eq("id", inserted.id);

  return {
    row: { ...inserted, payload: updatedPayload },
    created: true,
    notified: true,
    push,
  };
}

async function authorizedRooms(
  req: Request,
  admin: ReturnType<typeof createClient>,
  familyRoomId?: string,
) {
  const authHeader = req.headers.get("Authorization") || "";
  const cronHeader = req.headers.get("x-honeycomb-cron-secret") || "";
  const cronAllowed =
    (!!CRON_SECRET && cronHeader === CRON_SECRET) ||
    (!!SUPABASE_SERVICE_ROLE_KEY &&
      authHeader === `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`);

  if (cronAllowed && !familyRoomId) {
    const { data, error } = await admin
      .from("family_rooms")
      .select("id, owner_id, name");
    if (error) throw error;
    return { rooms: data || [], userMode: false };
  }

  if (!authHeader.startsWith("Bearer ")) {
    return { rooms: [], userMode: true, error: "missing auth" };
  }
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return { rooms: [], userMode: true, error: "invalid auth" };
  }

  let query = admin
    .from("family_room_members")
    .select("room_id, family_rooms(id, owner_id, name)")
    .eq("user_id", userData.user.id)
    .eq("active", true);
  if (familyRoomId) query = query.eq("room_id", familyRoomId);
  const { data, error } = await query;
  if (error) throw error;
  const rooms = (data || [])
    .map((row) => {
      const room = row.family_rooms;
      return Array.isArray(room) ? room[0] : room;
    })
    .filter(Boolean) as FamilyRoom[];
  return { rooms, userMode: true };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method not allowed" });
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return json(500, { error: "daily surprise function is not configured" });
  }

  let body: { family_room_id?: string; mode?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  try {
    const { rooms, userMode, error } = await authorizedRooms(
      req,
      admin,
      body.family_room_id,
    );
    if (error) return json(userMode ? 401 : 403, { error });
    if (!rooms.length) return json(200, { processed: 0, results: [] });

    const now = new Date();
    const results: Array<Record<string, unknown>> = [];
    for (const room of rooms) {
      results.push({
        room_id: room.id,
        ...(await createDueSurpriseForRoom(admin, room, now)),
      });
    }
    return json(200, { processed: rooms.length, results });
  } catch (error) {
    console.error("process daily surprises failed", error);
    return json(500, { error: "daily surprise processing failed" });
  }
});
