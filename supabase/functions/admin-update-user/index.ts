import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
const PROTECTED_EMAIL = "bruno.cesar@deva.com.br";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
function ok(extra?: object) { return new Response(JSON.stringify({ ok: true, ...extra }), { headers: CORS_HEADERS }); }
function fail(message: string, status = 200) {
  console.error("[admin-update-user] Erro:", message);
  return new Response(JSON.stringify({ ok: false, error: message }), { status, headers: CORS_HEADERS });
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
      return fail("Apenas administradores podem editar usuários.", 403);
    }

    const body = await req.json();
    const { user_id, action } = body;
    if (!user_id) return fail("Usuário não informado.");

    const { data: target, error: targetErr } = await admin.from("profiles").select("*").eq("id", user_id).single();
    if (targetErr || !target) return fail("Usuário não encontrado.");

    if (caller.user_type === "admin_area") {
      if (target.filial_id !== caller.filial_id) return fail("Você só pode editar usuários da sua própria filial.", 403);
      if (target.user_type === "admin_geral") return fail("Você não pode editar um administrador geral.", 403);
    }
    if (target.email === PROTECTED_EMAIL && callerData.user.id !== target.id) {
      return fail("Este usuário está protegido e só pode ser editado por ele mesmo.", 403);
    }

    if (action === "toggle_active") {
      if (target.email === PROTECTED_EMAIL && body.is_active === false) {
        return fail("Este usuário está protegido e não pode ser desativado.", 403);
      }
      const { error: updErr } = await admin.from("profiles").update({ is_active: !!body.is_active }).eq("id", user_id);
      if (updErr) return fail("Falha ao atualizar status: " + updErr.message);
      return ok();
    }

    // action === "update_profile" (default)
    const patch: Record<string, unknown> = {};
    for (const field of ["name", "user_type", "filial_id"]) {
      if (field in body) patch[field] = body[field];
    }
    if (caller.user_type === "admin_area") {
      if (patch.user_type === "admin_geral") return fail("Você não pode promover a administrador geral.", 403);
      if ("filial_id" in patch && patch.filial_id !== caller.filial_id) return fail("Você não pode mover um usuário para outra filial.", 403);
    }
    if (Object.keys(patch).length === 0) return fail("Nada para atualizar.");

    const { error: updErr } = await admin.from("profiles").update(patch).eq("id", user_id);
    if (updErr) return fail("Falha ao atualizar perfil: " + updErr.message);
    return ok();
  } catch (e) {
    return fail(String((e as any)?.message || e));
  }
});
