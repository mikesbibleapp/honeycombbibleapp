import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

type EncouragementPayload = {
  title: string;
  opening_line: string;
  reflection: string;
  scripture: {
    reference: string;
    text: string;
  };
  prayer_or_prompt: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") || "";
const OPENAI_MODEL = Deno.env.get("OPENAI_MODEL") || "gpt-5.2";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function centralDateString() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Chicago",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${byType.year}-${byType.month}-${byType.day}`;
}

function cleanText(value: unknown, maxLength: number) {
  return String(value || "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

function validatePayload(value: unknown): EncouragementPayload | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const source = value as Record<string, unknown>;
  const scripture = source.scripture as Record<string, unknown> | undefined;
  if (!scripture || typeof scripture !== "object" || Array.isArray(scripture)) {
    return null;
  }
  const payload: EncouragementPayload = {
    title: cleanText(source.title, 70),
    opening_line: cleanText(source.opening_line, 130),
    reflection: cleanText(source.reflection, 420),
    scripture: {
      reference: cleanText(scripture.reference, 80),
      text: cleanText(scripture.text, 260),
    },
    prayer_or_prompt: cleanText(source.prayer_or_prompt, 140),
  };
  if (
    !payload.title ||
    !payload.opening_line ||
    !payload.reflection ||
    !payload.scripture.reference ||
    !payload.scripture.text ||
    !payload.prayer_or_prompt
  ) {
    return null;
  }
  return payload;
}

async function fallbackPayload(adminClient: ReturnType<typeof createClient>) {
  const { data, error } = await adminClient.rpc("daily_encouragement_fallback");
  if (error) throw error;
  const valid = validatePayload(data);
  if (valid) return valid;
  return {
    title: "Sweeter Than Honey",
    opening_line: "God's voice was never meant to feel far away.",
    reflection:
      "The Bible is not just a book to finish. It is a quiet place to meet with God. Even one chapter today can steady your heart and remind you that He is near.",
    scripture: {
      reference: "Psalm 119:103",
      text: "How sweet are your promises to my taste, more than honey to my mouth!",
    },
    prayer_or_prompt: "God, help me love Your words today.",
  };
}

function extractOutputText(response: Record<string, unknown>) {
  const direct = cleanText(response.output_text, 5000);
  if (direct) return direct;
  const output = response.output;
  if (!Array.isArray(output)) return "";
  for (const item of output) {
    const content = (item as { content?: unknown }).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      const text = cleanText((part as { text?: unknown }).text, 5000);
      if (text) return text;
    }
  }
  return "";
}

async function generateWithOpenAI() {
  if (!OPENAI_API_KEY) return null;

  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      input: [
        {
          role: "system",
          content:
            "You write short, peaceful Christian Bible encouragements for a family Bible reading app. Keep the tone warm, personal, simple, never preachy or condemning. Use public-domain WEB-style scripture wording.",
        },
        {
          role: "user",
          content:
            "Create today's Honeycomb encouragement. It should help kids and adults delight in God's Word like Psalm 119. Keep reflection to 2-5 short sentences. Avoid cheesy motivational quotes, guilt, and complicated theology words.",
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "daily_encouragement",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: [
              "title",
              "opening_line",
              "reflection",
              "scripture",
              "prayer_or_prompt",
            ],
            properties: {
              title: { type: "string", maxLength: 70 },
              opening_line: { type: "string", maxLength: 130 },
              reflection: { type: "string", maxLength: 420 },
              scripture: {
                type: "object",
                additionalProperties: false,
                required: ["reference", "text"],
                properties: {
                  reference: { type: "string", maxLength: 80 },
                  text: { type: "string", maxLength: 260 },
                },
              },
              prayer_or_prompt: { type: "string", maxLength: 140 },
            },
          },
        },
      },
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OpenAI request failed: ${res.status} ${text.slice(0, 180)}`);
  }

  const data = (await res.json()) as Record<string, unknown>;
  const outputText = extractOutputText(data);
  if (!outputText) throw new Error("OpenAI response did not include output text");
  const parsed = JSON.parse(outputText);
  return validatePayload(parsed);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST" && req.method !== "GET") {
    return json(405, { error: "method not allowed" });
  }
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return json(500, { error: "daily encouragement function is not configured" });
  }

  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) {
    return json(401, { error: "missing auth" });
  }

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

  const encouragementDate = centralDateString();
  const url = new URL(req.url);
  const refresh = url.searchParams.get("refresh") === "1";

  if (!refresh) {
    const { data: cached, error: cacheError } = await adminClient
      .from("daily_encouragements")
      .select("encouragement_date, payload, source, created_at")
      .eq("encouragement_date", encouragementDate)
      .maybeSingle();
    if (cacheError) return json(500, { error: "cache lookup failed" });
    if (cached && validatePayload(cached.payload)) {
      return json(200, cached as Record<string, unknown>);
    }
  }

  let source = "ai";
  let payload: EncouragementPayload | null = null;
  try {
    payload = await generateWithOpenAI();
  } catch (error) {
    console.warn("daily-encouragement OpenAI fallback", error);
  }
  if (!payload) {
    source = "fallback";
    payload = await fallbackPayload(adminClient);
  }

  const { data: saved, error: saveError } = await adminClient
    .from("daily_encouragements")
    .upsert(
      {
        encouragement_date: encouragementDate,
        payload,
        source,
      },
      { onConflict: "encouragement_date" },
    )
    .select("encouragement_date, payload, source, created_at")
    .single();

  if (saveError) return json(500, { error: "cache save failed" });
  return json(200, saved as Record<string, unknown>);
});
