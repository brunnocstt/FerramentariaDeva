-- Suporte aos dois novos fluxos de redefinição de senha (troca de link por código/senha
-- temporária, pra evitar que o firewall corporativo "clique" no link antes do usuário e
-- invalide o token de uso único).

-- 1) Colaborador precisa trocar a senha temporária no próximo login (fluxo do admin).
alter table public.profiles add column must_change_password boolean not null default false;
grant update (must_change_password) on public.profiles to authenticated;

-- 2) Código de 6 dígitos (fluxo de auto-atendimento) reaproveita password_reset_tokens,
-- só ganha um contador de tentativas erradas pra travar depois de algumas tentativas.
alter table public.password_reset_tokens add column attempts integer not null default 0;
