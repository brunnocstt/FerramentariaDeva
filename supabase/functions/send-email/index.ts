import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SMTP_USER  = Deno.env.get("SMTP_USER")!;
const SMTP_PASS  = Deno.env.get("ICLOUD_APP_PASSWORD")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") ?? Deno.env.get("ICLOUD_EMAIL")!;
const APP_URL    = Deno.env.get("APP_URL") ?? "https://ferramentariadeva.albusdata.com.br";
const FROM       = `"Ferramentaria Deva" <${FROM_EMAIL}>`;

const LOGO_URL = SUPABASE_URL + "/storage/v1/object/public/email-assets/deva-logo.png";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

const transporter = nodemailer.createTransport({
  host: "smtp.mail.me.com",
  port: 587,
  secure: false,
  auth: { user: SMTP_USER, pass: SMTP_PASS },
});

function buildHtml(title: string, body: string): string {
  const logo =
    '<img src="' + LOGO_URL + '" width="200" height="16" alt="IVECO DEVA" border="0" ' +
    'style="display:block;border:0;outline:none;text-decoration:none;box-shadow:none;filter:none;-ms-interpolation-mode:bicubic">';
  return (
    "<!DOCTYPE html>" +
    '<html lang="pt-BR"><head>' +
    '<meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<meta http-equiv="X-UA-Compatible" content="IE=edge">' +
    "<title>" + title + "</title>" +
    "<style>" +
    "body,table,td,p,a,h2{-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;box-sizing:border-box}" +
    "body{background:#F1F5F9;margin:0;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif}" +
    ".wrap{max-width:560px;margin:0 auto;border-radius:16px;overflow:hidden;border:1px solid #E2E8F0;box-shadow:0 2px 12px rgba(0,0,0,.07)}" +
    ".hdr{background:#1955FF;padding:22px 32px}" +
    ".body{padding:32px 36px;background:#ffffff}" +
    "h2{font-size:18px;font-weight:700;color:#0F172A;margin:0 0 16px;line-height:1.4}" +
    "p{font-size:14px;color:#475569;line-height:1.75;margin:0 0 20px}" +
    "p strong{color:#0F172A;font-weight:600}" +
    "a.btn{display:inline-block;background:#1955FF;color:#ffffff!important;font-weight:700;font-size:14px;text-decoration:none;padding:12px 28px;border-radius:10px;margin:4px 0 0;letter-spacing:-.1px}" +
    ".badge{display:inline-block;background:#EEF2FF;color:#1955FF;font-weight:700;font-size:11px;padding:4px 12px;border-radius:99px;margin-bottom:16px;letter-spacing:.3px}" +
    ".divider{height:1px;background:#F1F5F9;margin:20px 0}" +
    ".footer{background:#F8FAFC;padding:16px 32px;border-top:1px solid #E2E8F0;text-align:center;font-size:11px;color:#94A3B8;line-height:1.6}" +
    "@media only screen and (max-width:600px){" +
    ".body,.hdr,.footer{padding-left:20px!important;padding-right:20px!important}" +
    "a.btn{display:block!important;text-align:center}" +
    "}" +
    "</style></head><body>" +
    '<div class="wrap">' +
    '<div class="hdr">' + logo + "</div>" +
    '<div class="body"><h2>' + title + "</h2>" + body + "</div>" +
    '<div class="footer">E-mail automático &nbsp;·&nbsp; Ferramentaria Deva &nbsp;·&nbsp; © 2026 Albus Data</div>' +
    "</div></body></html>"
  );
}

async function sendMail(to: string, subject: string, body: string) {
  await transporter.sendMail({ from: FROM, to, subject, html: buildHtml(subject, body) });
  console.log(`[send-email] Enviado para ${to} — ${subject}`);
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function ok(extra?: object) {
  return new Response(JSON.stringify({ ok: true, ...extra }), { headers: CORS_HEADERS });
}
function err(message: string, status = 200) {
  console.error("[send-email] Erro:", message);
  return new Response(JSON.stringify({ ok: false, error: message }), { status, headers: CORS_HEADERS });
}

function genToken(): string {
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return Array.from(arr).map(b => b.toString(16).padStart(2, "0")).join("");
}

// Tipos de notificação operacional (webhook de banco) que geram e-mail.
// Os demais tipos ficam só no sino de notificações in-app, pra não gerar spam.
const NOTIFICATION_TYPES_COM_EMAIL = new Set(["afericao_proxima", "retirada_atrasada"]);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return err("Método não suportado.", 405);

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return err("JSON inválido.");
  }

  try {
    // ── A. Webhook de banco de dados (INSERT em notifications) ──
    if (payload.type === "INSERT" && payload.table === "notifications" && payload.record) {
      const record = payload.record;
      if (!NOTIFICATION_TYPES_COM_EMAIL.has(record.type)) return ok({ skipped: true });

      const { data: profile, error: pErr } = await admin
        .from("profiles")
        .select("email,name,is_active")
        .eq("id", record.user_id)
        .single();
      if (pErr || !profile || !profile.is_active) return ok({ skipped: true });

      await sendMail(
        profile.email,
        record.title,
        `<p>Olá, <strong>${profile.name}</strong>.</p><p>${record.body}</p>` +
          `<a class="btn" href="${APP_URL}">Abrir Ferramentaria Deva</a>`
      );
      return ok();
    }

    // ── B. Chamadas diretas do frontend ──
    const emailType = payload.emailType;

    if (emailType === "welcome_with_setup") {
      const authHeader = req.headers.get("Authorization") || "";
      if (authHeader !== `Bearer ${SERVICE_ROLE}`) return err("Não autorizado.", 401);
      const { email, name, setupLink } = payload;
      if (!email || !setupLink) return err("Parâmetros ausentes.");
      await sendMail(
        email,
        "Bem-vindo à Ferramentaria Deva — defina sua senha",
        `<span class="badge">NOVO ACESSO</span><p>Olá, <strong>${name || ""}</strong>.</p>` +
          `<p>Sua conta no sistema de Controle de Ferramentaria foi criada. Clique no botão abaixo para definir sua senha e acessar o sistema.</p>` +
          `<a class="btn" href="${setupLink}">Definir minha senha</a>` +
          `<div class="divider"></div><p>Se você não esperava este e-mail, ignore-o.</p>`
      );
      return ok();
    }

    if (emailType === "password_reset") {
      const authHeader = req.headers.get("Authorization") || "";
      const jwt = authHeader.replace("Bearer ", "");
      const { data: caller } = await admin.auth.getUser(jwt);
      if (!caller?.user) return err("Não autorizado.", 401);
      const { data: callerProfile } = await admin.from("profiles").select("user_type").eq("id", caller.user.id).single();
      if (!callerProfile || !["admin_geral", "admin_area"].includes(callerProfile.user_type)) {
        return err("Apenas administradores podem enviar redefinição de senha.", 403);
      }

      const { userId, email } = payload;
      if (!userId || !email) return err("Parâmetros ausentes.");

      await admin.from("password_reset_tokens").delete().eq("user_id", userId);
      const token = genToken();
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
      const { error: insErr } = await admin.from("password_reset_tokens").insert({ user_id: userId, token, expires_at: expiresAt });
      if (insErr) return err("Falha ao gerar token: " + insErr.message);

      const link = `${APP_URL}/?reset_token=${token}`;
      await sendMail(
        email,
        "Redefinição de senha — Ferramentaria Deva",
        `<span class="badge">SEGURANÇA</span><p>Foi solicitada a redefinição da sua senha.</p>` +
          `<p>Clique no botão abaixo para criar uma nova senha. Este link expira em <strong>1 hora</strong>.</p>` +
          `<a class="btn" href="${link}">Redefinir minha senha</a>` +
          `<div class="divider"></div><p>Se você não solicitou isso, ignore este e-mail e avise um administrador.</p>`
      );
      return ok();
    }

    if (emailType === "reset_password_verify") {
      const { token, newPassword } = payload;
      if (!token || !newPassword) return err("Parâmetros ausentes.");
      if (String(newPassword).length < 8) return err("A senha deve ter pelo menos 8 caracteres.");

      const { data: row, error: findErr } = await admin
        .from("password_reset_tokens")
        .select("id,user_id,expires_at,used_at")
        .eq("token", token)
        .single();
      if (findErr || !row) return err("Link inválido ou expirado.");
      if (row.used_at) return err("Este link já foi utilizado.");
      if (new Date(row.expires_at).getTime() < Date.now()) return err("Este link expirou. Solicite um novo.");

      const { error: updErr } = await admin.auth.admin.updateUserById(row.user_id, { password: newPassword });
      if (updErr) return err("Falha ao redefinir senha: " + updErr.message);

      await admin.from("password_reset_tokens").update({ used_at: new Date().toISOString() }).eq("id", row.id);
      return ok();
    }

    return err("emailType desconhecido.");
  } catch (e) {
    return err(String(e?.message || e));
  }
});
