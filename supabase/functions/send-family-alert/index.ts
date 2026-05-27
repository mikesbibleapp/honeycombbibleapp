import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AlertBody = {
  target_user_id?: string;
  challenge_id?: string;
  type?: string;
  title?: string;
  body?: string;
  url?: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") || "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") || "";
const VAPID_SUBJECT =
  Deno.env.get("VAPID_SUBJECT") || "mailto:mikebell@airafitness.com";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function cleanText(value: unknown, fallback: string, maxLength: number) {
  const text = String(value || fallback)
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return text.slice(0, maxLength);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { error: "method not allowed" });
  }
  if (
    !SUPABASE_URL ||
    !SUPABASE_ANON_KEY ||
    !SUPABASE_SERVICE_ROLE_KEY ||
    !VAPID_PUBLIC_KEY ||
    !VAPID_PRIVATE_KEY
  ) {
    return json(500, { error: "push alert function is not configured" });
  }

  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) {
    return json(401, { error: "missing auth" });
  }

  let payload: AlertBody = {};
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid json" });
  }

  const targetUserId = cleanText(payload.target_user_id, "", 80);
  if (!targetUserId) return json(400, { error: "target_user_id required" });
  const challengeId = cleanText(payload.challenge_id, "", 80);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } =
    await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json(401, { error: "invalid auth" });
  }
  const actorId = userData.user.id;

  const { data: membership, error: membershipError } = await adminClient
    .from("family_room_members")
    .select("room_id")
    .eq("user_id", actorId)
    .eq("active", true);

  if (membershipError) return json(500, { error: "membership lookup failed" });
  const roomIds = (membership || []).map((row) => row.room_id);
  let allowed = false;

  if (roomIds.length) {
    const { data: targetMembership, error: targetError } = await adminClient
      .from("family_room_members")
      .select("room_id")
      .eq("user_id", targetUserId)
      .eq("active", true)
      .in("room_id", roomIds)
      .limit(1);

    if (targetError) return json(500, { error: "target lookup failed" });
    allowed = !!(targetMembership && targetMembership.length);
  }

  if (!allowed && challengeId) {
    const { data: challenge, error: challengeError } = await adminClient
      .from("challenges")
      .select("id")
      .eq("id", challengeId)
      .eq("challenger_id", actorId)
      .eq("opponent_id", targetUserId)
      .limit(1);
    if (challengeError) return json(500, { error: "challenge lookup failed" });
    allowed = !!(challenge && challenge.length);
  }

  if (!allowed) {
    return json(403, { error: "target is not connected to this alert" });
  }

  const title = cleanText(payload.title, "Honeycomb Family Cup", 80);
  const body = cleanText(payload.body, "Open Honeycomb to see what happened.", 160);
  const url = cleanText(
    payload.url,
    "https://mikesbibleapp.github.io/honeycombbibleapp/?view=cup",
    220,
  );
  const type = cleanText(payload.type, "family-alert", 50);

  const { data: subscriptions, error: subError } = await adminClient
    .from("push_subscriptions")
    .select("id, endpoint, p256dh, auth")
    .eq("user_id", targetUserId);

  if (subError) return json(500, { error: "subscription lookup failed" });
  if (!subscriptions || !subscriptions.length) {
    return json(200, { sent: 0, failed: 0, skipped: true });
  }

  webpush.setVapidDetails(
    VAPID_SUBJECT,
    VAPID_PUBLIC_KEY,
    VAPID_PRIVATE_KEY,
  );

  let sent = 0;
  let failed = 0;
  const staleIds: string[] = [];
  const notification = JSON.stringify({
    title,
    body,
    url,
    tag: `honeycomb-${type}-${targetUserId}`,
    type,
  });

  await Promise.all(
    subscriptions.map(async (sub) => {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          },
          notification,
        );
        sent += 1;
      } catch (error) {
        failed += 1;
        const statusCode = Number((error as { statusCode?: number }).statusCode);
        if (statusCode === 404 || statusCode === 410) staleIds.push(sub.id);
        console.warn("send-family-alert failed", statusCode || error);
      }
    }),
  );

  if (staleIds.length) {
    await adminClient.from("push_subscriptions").delete().in("id", staleIds);
  }

  return json(200, { sent, failed, stale: staleIds.length });
});
