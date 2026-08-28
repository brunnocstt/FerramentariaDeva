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

// Código numérico de 6 dígitos (fluxo de auto-atendimento) — nada de link, pra não ser
// "clicado" antes da hora por firewall corporativo (Safe Links etc.), invalidando o token.
function genCode6(): string {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return String(100000 + (arr[0] % 900000));
}
function bigCodeBox(value: string): string {
  return `<table cellpadding="0" cellspacing="0" style="margin:0 auto 8px;"><tr><td style="background:#f0f4ff;border:1.5px dashed #1955FF;border-radius:10px;padding:18px 32px;">
    <span style="font-family:'Courier New',monospace;font-size:32px;font-weight:bold;letter-spacing:8px;color:#1955FF;">${value}</span>
  </td></tr></table>`;
}
const MAX_TENTATIVAS_CODIGO = 5;
const VALIDADE_CODIGO_MIN = 10;

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

    // ══════════════════════════════════════════════════════════════
    // CENÁRIO 1 — auto-atendimento: colaborador esqueceu a senha, pede ele mesmo,
    // recebe um código de 6 dígitos (nunca um link) e digita no próprio app.
    // ══════════════════════════════════════════════════════════════

    if (emailType === "forgot_password_request") {
      const email = String(payload.email || "").trim().toLowerCase();
      if (!email) return err("Parâmetros ausentes.");

      // Sempre responde "ok" independente de o e-mail existir ou não — não dá pra deixar
      // alguém descobrir quais e-mails têm conta só testando esse endpoint.
      const { data: target } = await admin
        .from("profiles").select("id,name,email,is_active").ilike("email", email).maybeSingle();

      if (target && target.is_active) {
        await admin.from("password_reset_tokens").delete().eq("user_id", target.id);
        const code = genCode6();
        const expiresAt = new Date(Date.now() + VALIDADE_CODIGO_MIN * 60 * 1000).toISOString();
        const { error: insErr } = await admin.from("password_reset_tokens")
          .insert({ user_id: target.id, token: code, expires_at: expiresAt, attempts: 0 });
        if (!insErr) {
          await sendMail(
            target.email,
            "Código de verificação — Ferramentaria Deva",
            `<p style="font-size:16px;color:#111827;margin:0 0 20px;font-weight:bold;">Olá, ${target.name}!</p>
             <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 28px;">
               Recebemos uma solicitação para redefinir a senha da sua conta. Digite o código abaixo no sistema pra continuar:
             </p>
             ${bigCodeBox(code)}
             <p style="font-size:13px;color:#9ca3af;text-align:center;margin:24px 0 32px;line-height:1.6;">
               Este código expira em ${VALIDADE_CODIGO_MIN} minutos. Se você não pediu isso, ignore este e-mail.
             </p>
             ${supportBox()}
             ${SIGNOFF}`
          );
        }
      }
      return ok();
    }

    if (emailType === "forgot_password_verify_code") {
      const email = String(payload.email || "").trim().toLowerCase();
      const code = String(payload.code || "").trim();
      if (!email || !code) return err("Parâmetros ausentes.");

      const { data: target } = await admin.from("profiles").select("id,is_active").ilike("email", email).maybeSingle();
      if (!target || !target.is_active) return err("Código inválido ou expirado.");

      const { data: row } = await admin.from("password_reset_tokens")
        .select("id,token,expires_at,used_at,attempts")
        .eq("user_id", target.id).order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (!row || row.used_at || new Date(row.expires_at).getTime() < Date.now()) {
        return err("Código inválido ou expirado.");
      }
      if (row.attempts >= MAX_TENTATIVAS_CODIGO) {
        return err("Muitas tentativas erradas. Solicite um novo código.");
      }
      if (row.token !== code) {
        await admin.from("password_reset_tokens").update({ attempts: row.attempts + 1 }).eq("id", row.id);
        return err("Código incorreto.");
      }
      return ok();
    }

    if (emailType === "forgot_password_set_new") {
      const email = String(payload.email || "").trim().toLowerCase();
      const code = String(payload.code || "").trim();
      const { newPassword } = payload;
      if (!email || !code || !newPassword) return err("Parâmetros ausentes.");
      if (String(newPassword).length < 8) return err("A senha deve ter pelo menos 8 caracteres.");

      const { data: target } = await admin.from("profiles").select("id,is_active").ilike("email", email).maybeSingle();
      if (!target || !target.is_active) return err("Código inválido ou expirado.");

      const { data: row } = await admin.from("password_reset_tokens")
        .select("id,token,expires_at,used_at,attempts")
        .eq("user_id", target.id).order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (!row || row.used_at || new Date(row.expires_at).getTime() < Date.now()) {
        return err("Código inválido ou expirado.");
      }
      if (row.attempts >= MAX_TENTATIVAS_CODIGO) return err("Muitas tentativas erradas. Solicite um novo código.");
      if (row.token !== code) {
        await admin.from("password_reset_tokens").update({ attempts: row.attempts + 1 }).eq("id", row.id);
        return err("Código incorreto.");
      }

      const { error: updErr } = await admin.auth.admin.updateUserById(target.id, { password: newPassword });
      if (updErr) return err("Falha ao redefinir senha: " + updErr.message);

      await admin.from("password_reset_tokens").update({ used_at: new Date().toISOString() }).eq("id", row.id);
      await admin.from("profiles").update({ must_change_password: false }).eq("id", target.id);
      return ok();
    }

    // ══════════════════════════════════════════════════════════════
    // CENÁRIO 2 — administrador reseta a senha de outra pessoa pelo painel: gera uma senha
    // temporária, manda por e-mail pro administrador (quem pediu) E pro colaborador afetado.
    // No próximo login, o colaborador é obrigado a trocar a senha antes de usar o sistema
    // (profiles.must_change_password).
    // ══════════════════════════════════════════════════════════════

    if (emailType === "admin_reset_temp_password") {
      const authHeader = req.headers.get("Authorization") || "";
      const jwt = authHeader.replace("Bearer ", "");
      const { data: caller } = await admin.auth.getUser(jwt);
      if (!caller?.user) return err("Não autorizado.", 401);
      const { data: callerProfile } = await admin.from("profiles")
        .select("user_type,filial_id,is_active,name,email").eq("id", caller.user.id).single();
      if (!callerProfile || !callerProfile.is_active || !["admin_geral", "admin_area"].includes(callerProfile.user_type)) {
        return err("Apenas administradores podem redefinir senha de outro usuário.", 403);
      }

      const { userId } = payload;
      if (!userId) return err("Parâmetros ausentes.");

      const { data: target, error: targetErr } = await admin
        .from("profiles").select("email,name,filial_id,is_active").eq("id", userId).single();
      if (targetErr || !target) return err("Usuário não encontrado.");
      if (!target.is_active) return err("Este usuário está inativo.");
      if (callerProfile.user_type === "admin_area" && target.filial_id !== callerProfile.filial_id) {
        return err("Você só pode redefinir a senha de usuários da sua própria filial.", 403);
      }
      if (target.email === SUPPORT_EMAIL && caller.user.id !== userId) {
        return err("Este usuário está protegido e só pode redefinir a própria senha.", 403);
      }

      const tempPassword = genCode6() + genCode6().slice(0, 2); // 8 dígitos, fácil de digitar/ditar
      const { error: updErr } = await admin.auth.admin.updateUserById(userId, { password: tempPassword });
      if (updErr) return err("Falha ao redefinir senha: " + updErr.message);

      const { error: flagErr } = await admin.from("profiles").update({ must_change_password: true }).eq("id", userId);
      if (flagErr) return err("Falha ao sinalizar troca obrigatória: " + flagErr.message);

      await sendMail(
        target.email,
        "Sua senha foi redefinida — Ferramentaria Deva",
        `<p style="font-size:16px;color:#111827;margin:0 0 20px;font-weight:bold;">Olá, ${target.name}!</p>
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 16px;">
           Um administrador (<strong>${callerProfile.name}</strong>) redefiniu a senha da sua conta no sistema de <strong>Controle de Ferramentaria</strong> da Deva Veículos.
         </p>
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 12px;">Use a senha temporária abaixo pra entrar:</p>
         ${bigCodeBox(tempPassword)}
         <p style="font-size:15px;color:#374151;line-height:1.7;margin:24px 0 32px;">
           Assim que você acessar, o sistema vai pedir pra você criar uma senha nova antes de continuar.
         </p>
         ${btn("Abrir Ferramentaria Deva", APP_URL)}
         <div style="height:1px;background:#e5e7eb;margin:32px 0;"></div>
         ${supportBox()}
         ${SIGNOFF}`
      );

      if (callerProfile.email && callerProfile.email !== target.email) {
        await sendMail(
          callerProfile.email,
          "Senha temporária gerada — Ferramentaria Deva",
          `<p style="font-size:16px;color:#111827;margin:0 0 20px;font-weight:bold;">Olá, ${callerProfile.name}!</p>
           <p style="font-size:15px;color:#374151;line-height:1.7;margin:0 0 16px;">
             Você solicitou a redefinição de senha de <strong>${target.name}</strong> (${target.email}). A mesma senha temporária abaixo também foi enviada diretamente pra ele(a):
           </p>
           ${bigCodeBox(tempPassword)}
           <p style="font-size:13px;color:#9ca3af;text-align:center;margin:24px 0 32px;line-height:1.6;">
             No primeiro login, o sistema vai exigir que essa pessoa crie uma senha nova antes de continuar.
           </p>
           ${supportBox()}
           ${SIGNOFF}`
        );
      }
      return ok();
    }

    return err("emailType desconhecido.");
  } catch (e) {
    return err(String(e?.message || e));
  }
});
