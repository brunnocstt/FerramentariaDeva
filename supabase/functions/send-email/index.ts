import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SMTP_USER  = Deno.env.get("SMTP_USER")!;
const SMTP_PASS  = Deno.env.get("ICLOUD_APP_PASSWORD")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") ?? Deno.env.get("ICLOUD_EMAIL")!;
const APP_URL    = Deno.env.get("APP_URL") ?? "https://ferramentariadeva.albusdata.com.br";
const SUPPORT_EMAIL = "bruno.cesar@deva.com.br";
const FROM       = `"Ferramentaria Deva" <${FROM_EMAIL}>`;

// Segredo interno (não é credencial de terceiros) que autentica a chamada feita pelo trigger
// Postgres (public.fn_notifica_email_operacional, via net.http_post) nesta function.
// Usado só porque o recurso nativo "Database Webhooks" do painel não está disponível
// neste projeto (schema supabase_functions ausente) — ver ARQUITETURA.md.
// Definido só como secret da function (painel → Edge Functions → send-email → Secrets),
// nunca hardcoded aqui.
const INTERNAL_WEBHOOK_SECRET = Deno.env.get("INTERNAL_WEBHOOK_SECRET")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

const transporter = nodemailer.createTransport({
  host: "smtp.mail.me.com",
  port: 587,
  secure: false,
  auth: { user: SMTP_USER, pass: SMTP_PASS },
});

// Wordmark IVECO DEVA — PNG rasterizado (SVG inline não renderiza na maioria dos clientes de
// e-mail, principalmente Outlook), hospedado no próprio domínio do app via GitHub Pages.
const LOGO_URL = "https://ferramentariadeva.albusdata.com.br/assets/deva-logo-email.png";
const LOGO_IMG = `<img src="${LOGO_URL}" width="160" alt="IVECO DEVA" style="display:block;margin:0 auto;border:0;outline:none;text-decoration:none;">`;

// Botão call-to-action — tabela em vez de <a> solto, pra renderizar direito no Outlook.
function btn(label: string, href: string): string {
  return `<table cellpadding="0" cellspacing="0" style="margin:0 auto 8px;"><tr><td style="border-radius:8px;background:#1955FF;">
    <a href="${href}" style="display:inline-block;padding:14px 32px;color:#ffffff;font-weight:bold;font-size:14px;text-decoration:none;border-radius:8px;font-family:Arial,Helvetica,sans-serif;">${label}</a>
  </td></tr></table>`;
}
function badge(label: string): string {
  return `<span style="display:inline-block;background:#eef2ff;color:#1955FF;font-weight:bold;font-size:11px;padding:4px 12px;border-radius:99px;margin-bottom:16px;letter-spacing:.5px;">${label}</span>`;
}
function supportBox(): string {
  return `<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4ff;border-left:3px solid #1955FF;border-radius:4px;margin-bottom:32px;"><tr><td style="padding:16px 20px;">
    <p style="font-size:13px;color:#374151;margin:0;line-height:1.6;">Dúvidas ou problemas? Entre em contato com o time de suporte:<br>
    <a href="mailto:${SUPPORT_EMAIL}" style="color:#1955FF;font-weight:bold;text-decoration:none;">${SUPPORT_EMAIL}</a></p>
  </td></tr></table>`;
}
const SIGNOFF = `<p style="font-size:14px;color:#374151;margin:0 0 4px;">Atenciosamente,</p>
  <p style="font-size:14px;color:#111827;font-weight:bold;margin:0;">Equipe de Ferramentaria – Deva Veículos</p>`;

// Casca do e-mail — cabeçalho preto com a logo, barra azul, corpo branco (recebe o HTML já
// pronto de cada tipo de e-mail) e rodapé cinza. Mesmo layout usado nos outros sistemas da Deva.
function buildHtml(title: string, bodyHtml: string): string {
  return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>${title}</title></head>
<body style="margin:0;padding:0;background:#ffffff;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;padding:40px 0;">
  <tr><td align="center" bgcolor="#ffffff">
    <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:10px;overflow:hidden;box-shadow:0 4px 16px rgba(0,0,0,0.10);max-width:600px;">
      <tr><td style="background:#000000;padding:28px 40px;text-align:center;">
        ${LOGO_IMG}
        <p style="color:#888888;font-size:11px;margin:8px 0 0;letter-spacing:1px;">CONTROLE DE FERRAMENTARIA</p>
      </td></tr>
      <tr><td style="background:#1955FF;height:4px;"></td></tr>
      <tr><td bgcolor="#ffffff" style="padding:40px 48px 32px;background:#ffffff;">
        ${bodyHtml}
      </td></tr>
      <tr><td bgcolor="#f9fafb" style="background:#f9fafb;border-top:1px solid #e5e7eb;padding:20px 48px;">
        <p style="font-size:11px;color:#9ca3af;margin:0;text-align:center;line-height:1.6;">Este e-mail foi enviado automaticamente pelo sistema de Controle de Ferramentaria.</p>
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`;
}

async function sendMail(to: string, subject: string, bodyHtml: string) {
  const info = await transporter.sendMail({ from: FROM, to, subject, html: buildHtml(subject, bodyHtml) });
  console.log(`[send-email] Enviado para ${to} — ${subject} — from=${FROM} — resposta SMTP: ${JSON.stringify({
    messageId: info.messageId,
    envelope: info.envelope,
    accepted: info.accepted,
    rejected: info.rejected,
    response: info.response,
  })}`);
}

// CORS restrito ao domínio real do app — nada de "*" numa function que aceita POST não autenticado.
const ALLOWED_ORIGIN = "https://ferramentariadeva.albusdata.com.br";
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
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
const NOTIFICATION_TYPES_COM_EMAIL = new Set([
  "afericao_proxima",
  "retirada_atrasada",
  "licenca_proxima",
  "ferramenta_danificada",
]);

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
    // Chamada feita pelo trigger public.fn_notifica_email_operacional (via net.http_post),
    // autenticada por um segredo interno (não é credencial de terceiros) em vez do Database
    // Webhook nativo do painel, indisponível neste projeto (schema supabase_functions ausente).
    if (payload.type === "INSERT" && payload.table === "notifications" && payload.record) {
      const webhookSecret = req.headers.get("x-webhook-secret") || "";
      if (webhookSecret !== INTERNAL_WEBHOOK_SECRET) return err("Não autorizado.", 401);

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
        `<p style="font-size:16px;color:#111827;margin:0 0 20px;font-weight:bold;">Olá, ${profile.name}!</p>
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 32px;">${record.body}</p>
         ${btn("Abrir Ferramentaria Deva", APP_URL)}
         <div style="height:1px;background:#e5e7eb;margin:32px 0;"></div>
         ${supportBox()}
         ${SIGNOFF}`
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
        `${badge("NOVO ACESSO")}
         <p style="font-size:16px;color:#111827;margin:0 0 20px;font-weight:bold;">Olá, ${name || ""}!</p>
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 16px;">
           Sua conta no sistema de <strong>Controle de Ferramentaria</strong> da Deva Veículos foi criada.
         </p>
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 32px;">
           Clique no botão abaixo para definir sua senha e acessar o sistema.
         </p>
         ${btn("Definir minha senha", setupLink)}
         <p style="font-size:13px;color:#9ca3af;text-align:center;margin:24px 0 32px;line-height:1.6;">
           Se você não esperava este e-mail, ignore-o.
         </p>
         ${supportBox()}
         ${SIGNOFF}`
      );
      return ok();
    }

    if (emailType === "password_reset") {
      const authHeader = req.headers.get("Authorization") || "";
      const jwt = authHeader.replace("Bearer ", "");
      const { data: caller } = await admin.auth.getUser(jwt);
      if (!caller?.user) return err("Não autorizado.", 401);
      const { data: callerProfile } = await admin.from("profiles").select("user_type,filial_id,is_active").eq("id", caller.user.id).single();
      if (!callerProfile || !callerProfile.is_active || !["admin_geral", "admin_area"].includes(callerProfile.user_type)) {
        return err("Apenas administradores podem enviar redefinição de senha.", 403);
      }

      const { userId } = payload;
      if (!userId) return err("Parâmetros ausentes.");

      // E-mail e nome sempre vêm do cadastro no banco — nunca do que o cliente mandar no payload,
      // pra um admin_area não conseguir gerar um link de reset válido e mandar pra um endereço
      // arbitrário dele mesmo.
      const { data: target, error: targetErr } = await admin
        .from("profiles")
        .select("email,name,filial_id,is_active")
        .eq("id", userId)
        .single();
      if (targetErr || !target) return err("Usuário não encontrado.");
      if (!target.is_active) return err("Este usuário está inativo.");
      if (callerProfile.user_type === "admin_area" && target.filial_id !== callerProfile.filial_id) {
        return err("Você só pode redefinir a senha de usuários da sua própria filial.", 403);
      }
      if (target.email === SUPPORT_EMAIL && caller.user.id !== userId) {
        return err("Este usuário está protegido e só pode redefinir a própria senha.", 403);
      }

      await admin.from("password_reset_tokens").delete().eq("user_id", userId);
      const token = genToken();
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
      const { error: insErr } = await admin.from("password_reset_tokens").insert({ user_id: userId, token, expires_at: expiresAt });
      if (insErr) return err("Falha ao gerar token: " + insErr.message);

      const link = `${APP_URL}/?reset_token=${token}`;
      await sendMail(
        target.email,
        "Redefinição de senha — Ferramentaria Deva",
        `<p style="font-size:16px;color:#111827;margin:0 0 20px;font-weight:bold;">Olá, ${target.name}!</p>
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 16px;">
           Um administrador solicitou a redefinição da senha da sua conta no sistema de <strong>Controle de Ferramentaria</strong> da Deva Veículos.
         </p>
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 32px;">
           Clique no botão abaixo para criar uma nova senha. Este link expira em <strong>1 hora</strong>.
         </p>
         ${btn("Redefinir minha senha", link)}
         <p style="font-size:13px;color:#9ca3af;text-align:center;margin:24px 0 32px;line-height:1.6;">
           Se você não esperava isso, ignore este e-mail e avise um administrador.
         </p>
         ${supportBox()}
         ${SIGNOFF}`
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
