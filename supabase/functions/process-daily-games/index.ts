import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import webpush from "npm:web-push@3.6.7";

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

const GAME_NAMES: Record<string, string> = {
  honey_drop: "Honey Drop",
  manna_mover: "Manna Mover",
  shepherd_dash: "Shepherd Dash",
  ark_match: "Ark Match",
  bible_memory: "Honey Memory",
  finish_verse: "Finish the Verse",
  match_book: "Match the Book",
  who_said: "Who Said It?",
};

type Room = {
  id: string;
  owner_id: string;
  name?: string | null;
};

type Member = {
  user_id: string;
  joined_at?: string | null;
};

type Progress = {
  user_id: string;
  state?: Record<string, unknown> | null;
  tz_offset_minutes?: number | null;
};

type Subscription = {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function centralDateString(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Chicago",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${byType.year}-${byType.month}-${byType.day}`;
}

function localDateFromOffset(now: Date, offsetMinutes: number) {
  return new Date(now.getTime() - offsetMinutes * 60_000);
}

function pushHourFromState(state?: Record<string, unknown> | null) {
  const settings =
    state && typeof state.settings === "object" && !Array.isArray(state.settings)
      ? (state.settings as Record<string, unknown>)
      : {};
  const raw = Number(
    state?.dailyGamePushHour ?? settings.dailyGamePushHour ?? 8,
  );
  if (!Number.isFinite(raw)) return 8;
  return Math.max(8, Math.min(20, Math.round(raw)));
}

function offsetFromProgress(progress?: Progress | null) {
  const raw = Number(progress?.tz_offset_minutes);
  return Number.isFinite(raw) ? raw : 300;
}

function dueForPush(now: Date, progress?: Progress | null) {
  const offset = offsetFromProgress(progress);
  const local = localDateFromOffset(now, offset);
  const localHour = local.getHours();
  const pushHour = pushHourFromState(progress?.state || {});
  if (localHour < 8 || localHour >= 21) return false;
  return localHour >= pushHour;
}

function canUseCron(req: Request) {
  const authHeader = req.headers.get("Authorization") || "";
  const cronHeader = req.headers.get("x-honeycomb-cron-secret") || "";
  return (
    (!!CRON_SECRET && cronHeader === CRON_SECRET) ||
    (!!SUPABASE_SERVICE_ROLE_KEY &&
      authHeader === `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`)
  );
}

async function roomsForRequest(
  req: Request,
  admin: ReturnType<typeof createClient>,
  familyRoomId?: string,
) {
  if (canUseCron(req)) {
    let query = admin.from("family_rooms").select("id, owner_id, name");
    if (familyRoomId) query = query.eq("id", familyRoomId);
    const { data, error } = await query;
    if (error) throw error;
    return { rooms: (data || []) as Room[], userMode: false };
  }

  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) {
    return { rooms: [] as Room[], userMode: true, error: "missing auth" };
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return { rooms: [] as Room[], userMode: true, error: "invalid auth" };
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
    .filter(Boolean) as Room[];
  return { rooms, userMode: true };
}

async function dailyGameForRoom(
  admin: ReturnType<typeof createClient>,
  roomId: string,
  gameDate: string,
) {
  const { data, error } = await admin.rpc("daily_game_for_room", {
    p_family_room_id: roomId,
    p_game_date: gameDate,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
}

async function loadRoomMembers(
  admin: ReturnType<typeof createClient>,
  roomId: string,
) {
  const { data, error } = await admin
    .from("family_room_members")
    .select("user_id, joined_at")
    .eq("room_id", roomId)
    .eq("active", true);
  if (error) throw error;
  return (data || []) as Member[];
}

async function loadProgress(
  admin: ReturnType<typeof createClient>,
  userIds: string[],
) {
  if (!userIds.length) return new Map<string, Progress>();
  const { data, error } = await admin
    .from("user_progress")
    .select("user_id, state, tz_offset_minutes")
    .in("user_id", userIds);
  if (error) throw error;
  return new Map((data || []).map((row: Progress) => [row.user_id, row]));
}

async function pushDailyGame(
  admin: ReturnType<typeof createClient>,
  userId: string,
  roomId: string,
  gameDate: string,
  gameId: string,
) {
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    return { sent: 0, failed: 0, stale: 0, skipped: "vapid missing" };
  }

  const { data: subscriptions, error } = await admin
    .from("push_subscriptions")
    .select("id, endpoint, p256dh, auth")
    .eq("user_id", userId);
  if (error) throw error;
  if (!subscriptions?.length) {
    return { sent: 0, failed: 0, stale: 0, skipped: "no subscriptions" };
  }

  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
  const title = "🐝 Your Game of the Day is ready";
  const name = GAME_NAMES[gameId] || "Game of the Day";
  const body = `${name}: play it, then read to double your Cup points.`;
  const payload = JSON.stringify({
    title,
    body,
    url: "https://mikesbibleapp.github.io/honeycombbibleapp/?view=today&game=1",
    tag: `honeycomb-daily-game-${gameDate}`,
    type: "daily-game",
  });

  let sent = 0;
  let failed = 0;
  const staleIds: string[] = [];
  await Promise.all(
    (subscriptions as Subscription[]).map(async (sub) => {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          },
          payload,
        );
        sent += 1;
      } catch (error) {
        failed += 1;
        const statusCode = Number((error as { statusCode?: number }).statusCode);
        if (statusCode === 404 || statusCode === 410) staleIds.push(sub.id);
        console.warn("daily game push failed", statusCode || error);
      }
    }),
  );

  if (staleIds.length) {
    await admin.from("push_subscriptions").delete().in("id", staleIds);
  }

  if (sent > 0) {
    await admin.from("daily_game_pushes").upsert(
      {
        family_room_id: roomId,
        user_id: userId,
        game_date: gameDate,
        game_id: gameId,
      },
      { onConflict: "user_id,game_date" },
    );
  }
  return { sent, failed, stale: staleIds.length };
}

async function processRoom(
  admin: ReturnType<typeof createClient>,
  room: Room,
  now: Date,
  force = false,
) {
  const gameDate = centralDateString(now);
  const game = await dailyGameForRoom(admin, room.id, gameDate);
  if (!game?.game_id) return { room_id: room.id, skipped: "no daily game" };

  const members = await loadRoomMembers(admin, room.id);
  const userIds = members.map((member) => member.user_id);
  const progressById = await loadProgress(admin, userIds);
  const { data: alreadyRows } = await admin
    .from("daily_game_pushes")
    .select("user_id")
    .eq("family_room_id", room.id)
    .eq("game_date", gameDate);
  const already = new Set((alreadyRows || []).map((row) => row.user_id));

  let due = 0;
  let sent = 0;
  let failed = 0;
  let skipped = 0;

  for (const member of members) {
    if (already.has(member.user_id)) {
      skipped += 1;
      continue;
    }
    const progress = progressById.get(member.user_id) || null;
    if (!force && !dueForPush(now, progress)) {
      skipped += 1;
      continue;
    }
    due += 1;
    const push = await pushDailyGame(
      admin,
      member.user_id,
      room.id,
      gameDate,
      game.game_id,
    );
    sent += Number(push.sent || 0);
    failed += Number(push.failed || 0);
  }

  return {
    room_id: room.id,
    game_date: gameDate,
    game_id: game.game_id,
    due,
    sent,
    failed,
    skipped,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method not allowed" });
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return json(500, { error: "daily game function is not configured" });
  }

  let body: { family_room_id?: string; mode?: string; force?: boolean } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  try {
    const { rooms, userMode, error } = await roomsForRequest(
      req,
      admin,
      body.family_room_id,
    );
    if (error) return json(userMode ? 401 : 403, { error });
    if (!rooms.length) return json(200, { processed: 0, results: [] });
    const force = body.force === true || body.mode === "force";
    const now = new Date();
    const results = [];
    for (const room of rooms) {
      results.push(await processRoom(admin, room, now, force));
    }
    return json(200, { processed: rooms.length, results });
  } catch (error) {
    console.error("process daily games failed", error);
    return json(500, { error: "daily game processing failed" });
  }
});
