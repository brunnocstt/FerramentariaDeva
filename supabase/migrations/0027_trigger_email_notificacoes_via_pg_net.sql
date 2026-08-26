-- Substitui o "Database Webhook" nativo (indisponível neste projeto por falta do schema
-- interno supabase_functions, que só a Supabase consegue provisionar do lado deles) por um
-- trigger direto usando pg_net. Dispara em todo INSERT em notifications; a function send-email
-- decide se aquele "type" gera e-mail ou não (NOTIFICATION_TYPES_COM_EMAIL).
--
-- Autenticação: segredo interno (não é credencial de terceiros/usuário), comparado no lado da
-- edge function via header x-webhook-secret. Definido como secret da function
-- INTERNAL_WEBHOOK_SECRET (painel → Edge Functions → send-email → Secrets).
--
-- IMPORTANTE: o valor real do segredo abaixo (<INTERNAL_WEBHOOK_SECRET_VALUE>) NÃO fica neste
-- arquivo nem em nenhum lugar do controle de versão — só existe de fato dentro do banco de
-- produção (nesta função) e no secret do edge function. Antes de reaplicar esta migration em
-- qualquer ambiente, substitua o placeholder pelo valor real (consulte o secret já configurado
-- no painel, ou gere um novo com `select encode(gen_random_bytes(32),'hex');` e atualize os
-- dois lados juntos).
--
-- NOTA: esta migration foi aplicada originalmente direto no SQL Editor do painel (não via
-- apply_migration), por isso não aparece na tabela supabase_migrations.schema_migrations do
-- projeto — mas o trigger está ativo em produção. Arquivo criado aqui só pra manter o histórico
-- local em dia com o que realmente existe no banco.

create or replace function public.fn_notifica_email_operacional()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://zdwkdfsqxkcrnkovdvba.supabase.co/functions/v1/send-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '<INTERNAL_WEBHOOK_SECRET_VALUE>'
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'notifications',
      'record', to_jsonb(new)
    ),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;

revoke all on function public.fn_notifica_email_operacional() from public, anon, authenticated;

drop trigger if exists trg_notifica_email_operacional on public.notifications;
create trigger trg_notifica_email_operacional
  after insert on public.notifications
  for each row
  execute function public.fn_notifica_email_operacional();
