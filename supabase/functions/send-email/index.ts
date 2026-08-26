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

// Wordmark IVECO DEVA em branco, pro cabeçalho preto — mesmo SVG usado no app (componente Logo).
const LOGO_SVG = `<svg width="160" viewBox="0 0 183 15" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M0.255224 0.551577H3.85268C4.00215 0.566281 4.07688 0.650527 4.07688 0.804314C4.07688 5.28925 4.07688 9.76194 4.07688 14.2224C4.07688 14.277 4.05502 14.3293 4.0161 14.3679C3.97718 14.4065 3.9244 14.4282 3.86936 14.4282L0.175548 14.4292C0.161522 14.4292 0.147684 14.4263 0.134922 14.4208C0.122159 14.4152 0.110752 14.4071 0.101431 14.397C0.0364746 14.326 0.00044619 14.2334 0.00044619 14.1372V0.84659C-0.00696552 0.653591 0.0779603 0.555253 0.255224 0.551577Z" fill="white"/><path d="M6.88079 0.551577H10.9785C13.0977 4.13769 15.2285 7.74402 17.3711 11.3706C17.4131 11.441 17.4598 11.498 17.511 11.5415C17.5188 11.5479 17.5279 11.5526 17.5377 11.5552C17.5474 11.5579 17.5576 11.5584 17.5676 11.5569C17.5776 11.5553 17.5871 11.5516 17.5956 11.5462C17.604 11.5407 17.6112 11.5334 17.6166 11.525C19.9353 7.90455 22.2456 4.29178 24.5475 0.686676C24.5877 0.622956 24.6667 0.577923 24.7847 0.551577H27.78L28.964 0.5865C28.9998 0.587726 29.018 0.606107 29.0186 0.641643C29.0236 0.891011 28.96 1.11924 28.8278 1.32633C26.4264 5.08706 24.029 8.85025 21.6356 12.6159C21.3102 13.1281 21.0646 13.4718 20.8991 13.647C19.2361 15.4079 15.9277 15.4686 14.236 13.7197C14.0062 13.4825 13.6931 13.0249 13.2966 12.3466C11.1416 8.66184 8.98232 4.97984 6.81872 1.3006C6.70445 1.10637 6.6501 0.890398 6.65566 0.652672C6.65628 0.618973 6.67326 0.598142 6.70662 0.590177L6.88079 0.551577Z" fill="white"/><path d="M34.7689 0.551577H46.8352C46.9859 0.565056 47.0615 0.65696 47.0621 0.82729C47.0665 1.73102 47.0658 2.63505 47.0603 3.53939C47.0584 3.81939 46.9207 3.95909 46.6471 3.95848C42.6021 3.95357 38.5569 3.95143 34.5113 3.95204C34.4798 3.95204 34.4641 3.96767 34.4641 3.99891V10.8219C34.4641 10.8767 34.486 10.9293 34.5251 10.9681C34.5642 11.0069 34.6173 11.0287 34.6725 11.0287H46.8787C46.9278 11.0287 46.975 11.0481 47.0097 11.0825C47.0445 11.117 47.064 11.1637 47.064 11.2125V14.1985C47.064 14.351 46.9871 14.4273 46.8333 14.4273C43.2025 14.4301 39.5615 14.3814 35.9316 14.4494C35.2608 14.4622 34.7717 14.4481 34.4641 14.4071C32.7816 14.1856 30.9936 13.1076 30.5109 11.4119C30.4244 11.1086 30.3824 10.635 30.3849 9.99109C30.391 8.14564 30.3917 6.30143 30.3867 4.45844C30.3802 2.2031 32.6288 0.691271 34.7689 0.551577Z" fill="white"/><path d="M55.0888 0.551565H67.0392C67.4404 0.543294 67.4497 0.926536 67.4506 1.21787C67.4518 1.93779 67.4487 2.65771 67.4413 3.37763C67.4395 3.53815 67.4083 3.69194 67.3478 3.83899C67.3358 3.86679 67.3137 3.88912 67.2857 3.90148C67.2097 3.93457 67.1399 3.95111 67.0763 3.95111C63.0159 3.95173 58.9701 3.95203 54.9387 3.95203C54.9145 3.95203 54.8905 3.95676 54.8682 3.96595C54.8458 3.97514 54.8255 3.98862 54.8084 4.0056C54.7912 4.02258 54.7776 4.04274 54.7684 4.06493C54.7591 4.08712 54.7543 4.1109 54.7543 4.13492V10.8219C54.7543 10.8765 54.7763 10.9289 54.8154 10.9675C54.8545 11.0061 54.9075 11.0278 54.9628 11.0278L67.2273 11.0296C67.2388 11.0296 67.2502 11.0323 67.2605 11.0376C67.2708 11.0429 67.2797 11.0505 67.2866 11.0599C67.3824 11.1874 67.4318 11.3301 67.4349 11.4882C67.4503 12.2921 67.4515 13.0962 67.4386 13.9007C67.4361 14.0508 67.4034 14.1926 67.3404 14.3262C67.3261 14.3556 67.3039 14.3755 67.2736 14.3859C67.194 14.4135 67.1128 14.4273 67.03 14.4273C63.4298 14.4301 59.8212 14.385 56.2219 14.4503C55.5604 14.4619 55.0712 14.446 54.7543 14.4025C52.8718 14.1442 50.9021 12.7988 50.6992 10.7759C50.6745 10.5278 50.664 10.1142 50.6677 9.53523C50.6782 7.88095 50.6822 6.22667 50.6798 4.57239C50.677 2.2472 52.9376 0.681151 55.0888 0.551565Z" fill="white"/><path d="M74.9784 0.551577H84.8481C85.1056 0.575472 85.3644 0.585888 85.6244 0.582824C85.9407 0.579148 86.361 0.687289 86.8853 0.907247C88.3983 1.54231 89.5369 2.65435 89.6823 4.34264V10.7125C89.5903 11.5452 89.2645 12.2547 88.7049 12.841C87.7025 13.8918 86.4456 14.4166 84.9342 14.4154C80.2723 14.4111 77.1454 14.4194 75.5538 14.4402C73.6453 14.465 71.8674 13.6333 70.9502 11.9404C70.6481 11.3844 70.5981 10.7796 70.5981 10.0664C70.5969 8.20446 70.5981 6.34248 70.6018 4.48049C70.6037 3.42911 71.1855 2.3768 72.0045 1.72612C72.8723 1.03622 73.8636 0.644706 74.9784 0.551577ZM74.6885 10.8219C74.6894 11.0131 74.8487 11.0351 74.9979 11.0342C78.4962 11.0305 81.993 11.0284 85.4882 11.0278C85.4949 11.0278 85.5012 11.0251 85.5059 11.0202C85.5106 11.0154 85.5133 11.0089 85.5133 11.002V4.0899C85.5133 4.05334 85.4986 4.01827 85.4726 3.99242C85.4465 3.96657 85.4111 3.95204 85.3743 3.95204H74.6977C74.6908 3.95204 74.6842 3.95475 74.6794 3.95958C74.6745 3.96441 74.6718 3.97095 74.6718 3.97778C74.6724 6.25762 74.678 8.539 74.6885 10.8219Z" fill="white"/><path d="M46.8024 5.89153H36.6206C36.5157 5.89153 36.4307 5.97588 36.4307 6.07994V8.91979C36.4307 9.02384 36.5157 9.10819 36.6206 9.10819H46.8024C46.9073 9.10819 46.9923 9.02384 46.9923 8.91979V6.07994C46.9923 5.97588 46.9073 5.89153 46.8024 5.89153Z" fill="white"/><path d="M177.201 12.4415C177.18 12.405 177.151 12.3746 177.115 12.3534C177.079 12.3323 177.038 12.3211 176.996 12.3211C173.663 12.3247 170.333 12.3257 167.007 12.3238C166.872 12.3238 166.765 12.4093 166.684 12.5802C166.54 12.8866 166.263 13.4083 165.853 14.1454C165.675 14.467 165.497 14.5222 165.117 14.5249C164.133 14.5323 163.149 14.5357 162.166 14.535C161.842 14.535 161.138 14.5562 161.348 14.0011C161.396 13.8755 161.478 13.711 161.596 13.5076C163.638 9.99435 165.672 6.47686 167.699 2.95508C168.108 2.24374 168.55 1.64575 169.024 1.16111C170.01 0.151076 171.555 -0.183456 172.934 0.0931768C174.353 0.377162 175.305 1.31183 176.05 2.59298C178.246 6.36841 180.44 10.1451 182.632 13.923C182.656 13.9665 182.686 14.0596 182.72 14.2024C182.726 14.2305 182.723 14.2575 182.709 14.2832C182.631 14.4272 182.521 14.501 182.379 14.5047C181.2 14.5366 180.021 14.5485 178.842 14.5406C178.629 14.5387 178.317 14.5112 178.211 14.3108C177.868 13.6632 177.531 13.0401 177.201 12.4415ZM175.147 8.72117C174.185 6.98785 173.221 5.25637 172.272 3.5157C172.192 3.37049 172.103 3.23999 172.005 3.12419C172.001 3.11913 171.995 3.1152 171.989 3.11275C171.983 3.1103 171.976 3.1094 171.97 3.11013C171.963 3.11085 171.957 3.11318 171.951 3.11691C171.945 3.12064 171.941 3.12566 171.937 3.13154L168.68 9.02629C168.675 9.03479 168.673 9.04432 168.673 9.05398C168.673 9.06363 168.676 9.07308 168.681 9.0814C168.686 9.08972 168.693 9.09663 168.701 9.10147C168.71 9.10631 168.719 9.1089 168.729 9.10901L175.208 9.10993C175.222 9.10985 175.235 9.10638 175.247 9.09982C175.259 9.09326 175.27 9.08381 175.277 9.07233C175.285 9.06085 175.289 9.0477 175.291 9.03405C175.292 9.0204 175.289 9.00668 175.284 8.99413C175.246 8.90774 175.2 8.81675 175.147 8.72117Z" fill="white"/><path d="M121.313 10.8947C120.86 13.0223 119.214 14.2584 117.075 14.445C116.611 14.4854 116.147 14.5066 115.681 14.5084C111.543 14.5237 107.405 14.5323 103.266 14.5341C102.985 14.5341 102.484 14.5452 102.483 14.2088C102.48 9.95056 102.474 5.69231 102.467 1.43407C102.467 1.16204 102.488 0.916346 102.532 0.697C102.539 0.658959 102.559 0.624646 102.59 0.599983C102.62 0.57532 102.658 0.561853 102.697 0.561901C107.238 0.560675 111.767 0.560368 116.283 0.560981C116.678 0.560981 117.071 0.588859 117.462 0.644614C119.343 0.912975 120.914 2.16104 121.309 4.03038C121.398 4.44701 121.445 4.86824 121.449 5.29406C121.463 6.63403 121.472 7.9743 121.476 9.31488C121.478 9.84732 121.423 10.3739 121.313 10.8947ZM106.764 11.0381H117.256C117.268 11.0381 117.28 11.0333 117.289 11.0246C117.297 11.016 117.302 11.0043 117.302 10.9921L117.301 4.06438C117.301 4.03708 117.29 4.0109 117.271 3.99159C117.251 3.97229 117.225 3.96145 117.198 3.96145H106.741C106.691 3.96145 106.644 3.98081 106.61 4.01528C106.575 4.04975 106.555 4.09651 106.555 4.14526V10.8313C106.555 10.8862 106.577 10.9387 106.616 10.9775C106.655 11.0163 106.708 11.0381 106.764 11.0381Z" fill="white"/><path d="M127.864 10.9875C127.864 11.0009 127.869 11.0138 127.879 11.0233C127.888 11.0327 127.901 11.0381 127.915 11.0381C132.054 11.0368 136.183 11.039 140.302 11.0445C140.658 11.0445 140.652 11.3579 140.654 11.6125C140.658 12.2049 140.653 13.0627 140.641 14.1858C140.638 14.4266 140.434 14.5102 140.232 14.5121C136.659 14.5543 133.083 14.5286 129.508 14.5268C128.966 14.5268 128.425 14.4912 127.887 14.4202C125.913 14.1591 124.325 12.9212 123.887 10.9563C123.797 10.5565 123.765 9.983 123.77 9.61355C123.789 8.05117 123.792 6.48849 123.779 4.9255C123.773 4.14921 123.975 3.42623 124.384 2.75655C125.253 1.33479 126.866 0.568305 128.536 0.565548C132.519 0.558808 136.503 0.558196 140.487 0.563711C140.507 0.563719 140.527 0.570267 140.543 0.582367C140.56 0.594468 140.571 0.611467 140.577 0.630802C140.601 0.70984 140.616 0.801744 140.621 0.906515C140.676 1.96893 140.678 2.89563 140.625 3.68663C140.613 3.86186 140.506 3.94978 140.302 3.95039C136.199 3.95836 132.108 3.96264 128.027 3.96326C127.984 3.96326 127.942 3.9803 127.912 4.01063C127.881 4.04097 127.864 4.08211 127.864 4.12501V10.9875Z" fill="white"/><path d="M153.957 14.99C153.124 14.99 152.259 14.997 151.516 14.6194C150.658 14.1835 150.063 13.4443 149.498 12.5573C147.095 8.78244 144.689 5.00915 142.281 1.23739C142.175 1.07073 142.124 0.88907 142.129 0.692394C142.13 0.676298 142.135 0.660649 142.144 0.647407C142.153 0.634165 142.166 0.623918 142.181 0.617952C142.26 0.586705 142.359 0.570161 142.479 0.568323C143.807 0.55178 145.152 0.550557 146.514 0.564649C146.567 0.565224 146.619 0.579118 146.664 0.605014C146.71 0.63091 146.748 0.667949 146.775 0.712614L153.249 11.345C153.259 11.3622 153.274 11.3763 153.292 11.3861C153.309 11.3959 153.329 11.4011 153.349 11.4011C153.369 11.4011 153.389 11.3959 153.407 11.3861C153.424 11.3763 153.439 11.3622 153.45 11.345L159.94 0.68688C159.966 0.64542 160.002 0.611187 160.044 0.587513C160.087 0.563838 160.135 0.551528 160.183 0.551781L164.363 0.570163C164.417 0.570322 164.468 0.590694 164.506 0.627095C164.545 0.663497 164.568 0.713169 164.571 0.76592C164.578 0.913886 164.523 1.06185 164.436 1.19879C162.141 4.79899 159.852 8.40318 157.569 12.0114C156.64 13.4791 155.791 14.7354 153.957 14.99Z" fill="white"/><path d="M140.098 5.89145C140.195 5.89145 140.289 5.92979 140.357 5.99804C140.426 6.06629 140.465 6.15886 140.465 6.25539V8.69913C140.465 8.80808 140.42 8.91257 140.341 8.98962C140.262 9.06666 140.154 9.10994 140.042 9.10994H130.322C130.21 9.10994 130.102 9.06666 130.023 8.98962C129.944 8.91257 129.899 8.80808 129.899 8.69913V6.25539C129.899 6.15886 129.938 6.06629 130.007 5.99804C130.076 5.92979 130.169 5.89145 130.266 5.89145H140.098Z" fill="white"/></svg>`;

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
        ${LOGO_SVG}
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
