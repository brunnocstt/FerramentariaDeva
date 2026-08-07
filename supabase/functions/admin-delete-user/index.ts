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
  console.error("[admin-delete-user] Erro:", message);
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

    const { data: caller } = await admin.from("profiles").select("user_type,is_active").eq("id", callerData.user.id).single();
    if (!caller || !caller.is_active || caller.user_type !== "admin_geral") {
      return fail("Apenas o administrador geral pode excluir usuários.", 403);
    }

    const { user_id } = await req.json();
    if (!user_id) return fail("Usuário não informado.");
    if (user_id === callerData.user.id) return fail("Você não pode excluir a própria conta.", 403);

    const { data: target } = await admin.from("profiles").select("email").eq("id", user_id).single();
    if (target?.email === PROTECTED_EMAIL) return fail("Este usuário está protegido e não pode ser excluído.", 403);

    const { error: delProfileErr } = await admin.from("profiles").delete().eq("id", user_id);
    if (delProfileErr) return fail("Falha ao excluir perfil: " + delProfileErr.message);

    const { error: delAuthErr } = await admin.auth.admin.deleteUser(user_id);
    if (delAuthErr) return fail("Perfil excluído, mas falhou ao excluir o login: " + delAuthErr.message);

    return ok();
  } catch (e) {
    return fail(String((e as any)?.message || e));
  }
});
