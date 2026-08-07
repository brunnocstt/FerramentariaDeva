import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APP_URL       = Deno.env.get("APP_URL") ?? "https://ferramentariadeva.albusdata.com.br";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
function ok(extra?: object) { return new Response(JSON.stringify({ ok: true, ...extra }), { headers: CORS_HEADERS }); }
function fail(message: string, status = 200) {
  console.error("[admin-create-user] Erro:", message);
  return new Response(JSON.stringify({ ok: false, error: message }), { status, headers: CORS_HEADERS });
}

function randomPassword(len = 24): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  return Array.from(arr).map(b => chars[b % chars.length]).join("");
}
function genToken(): string {
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return Array.from(arr).map(b => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return fail("Método não suportado.", 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace("Bearer ", "");
    const { data: callerData, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !callerData?.user) return fail("Não autorizado.", 401);

    const { data: caller } = await admin.from("profiles").select("user_type,filial_id,is_active").eq("id", callerData.user.id).single();
    if (!caller || !caller.is_active || !["admin_geral", "admin_area"].includes(caller.user_type)) {
      return fail("Apenas administradores podem criar usuários.", 403);
    }

    const body = await req.json();
    const { name, email, user_type, filial_id } = body;
    if (!name || !email || !user_type) return fail("Preencha nome, e-mail e tipo de usuário.");
    if (!["admin_geral", "admin_area", "colaborador"].includes(user_type)) return fail("Tipo de usuário inválido.");

    let finalFilialId = filial_id || null;
    if (caller.user_type === "admin_area") {
      if (user_type === "admin_geral") return fail("Você não pode criar um administrador geral.", 403);
      finalFilialId = caller.filial_id; // admin_area só cria dentro da própria filial
    }
    if (user_type !== "admin_geral" && !finalFilialId) return fail("Selecione a filial do usuário.");
    if (user_type === "admin_geral") finalFilialId = null;

    const tempPassword = randomPassword();
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
    });
    if (createErr || !created?.user) return fail("Falha ao criar usuário: " + (createErr?.message || "erro desconhecido"));

    const initials = String(name).trim().split(/\s+/).slice(0, 2).map((p: string) => p[0]?.toUpperCase() || "").join("") || "US";
    const { error: profErr } = await admin.from("profiles").insert({
      id: created.user.id,
      name, email, user_type, filial_id: finalFilialId, is_active: true, initials,
    });
    if (profErr) {
      await admin.auth.admin.deleteUser(created.user.id);
      return fail("Falha ao criar perfil: " + profErr.message);
    }

    const token = genToken();
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    await admin.from("password_reset_tokens").insert({ user_id: created.user.id, token, expires_at: expiresAt });
    const setupLink = `${APP_URL}/?reset_token=${token}`;

    await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${SERVICE_ROLE}` },
      body: JSON.stringify({ emailType: "welcome_with_setup", email, name, setupLink }),
    }).catch((e) => console.error("[admin-create-user] Falha ao enviar e-mail de boas-vindas:", e));

    return ok({ user: { id: created.user.id, name, email, user_type, filial_id: finalFilialId }, setupLink });
  } catch (e) {
    return fail(String((e as any)?.message || e));
  }
});
