-- ════════════════════════════════════════════════════════════════
-- Rodada 3 — Acesso operacional multi-filial + transferências
--
-- Duas coisas que hoje são a mesma (profiles.filial_id) precisam se
-- separar:
--   • filial "de casa" (profiles.filial_id, sem mudar de sentido):
--     onde a matrícula da pessoa vale, e pra admin_area, a filial da
--     qual ela é GESTORA (autoridade de aprovação).
--   • acesso operacional extra (acessos_filial, novo): filiais
--     adicionais cujo ferramental a pessoa pode ver/operar sem ser
--     gestora de lá. Só admin_geral concede.
-- ════════════════════════════════════════════════════════════════

create table public.acessos_filial (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  filial_id uuid not null references public.filiais(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(profile_id, filial_id)
);
alter table public.acessos_filial enable row level security;

create policy acessos_filial_select on public.acessos_filial for select to authenticated using (true);
create policy acessos_filial_write on public.acessos_filial for all to authenticated
  using (private.is_admin_geral()) with check (private.is_admin_geral());

create or replace function private.tem_acesso_filial(f_id uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select private.is_admin_geral()
      or f_id = (select filial_id from public.profiles where id = auth.uid())
      or exists (select 1 from public.acessos_filial where profile_id = auth.uid() and filial_id = f_id);
$$;
grant execute on function private.tem_acesso_filial(uuid) to authenticated;

-- ── Substitui filial_id = private.my_filial_id() por
--    private.tem_acesso_filial(filial_id) nas RLS de acesso/operação
--    (my_filial_id() continua existindo pro que é mesmo "filial de
--    casa", ex. matrícula, e pra fn_validate_admin_area_profile_update,
--    que é sobre editar OUTRO USUÁRIO — isso fica de fora de propósito).
-- ════════════════════════════════════════════════════════════════

drop policy unidade_select on public.ferramentas_unidade;
create policy unidade_select on public.ferramentas_unidade for select to authenticated
  using (private.tem_acesso_filial(filial_id));
drop policy unidade_insert on public.ferramentas_unidade;
create policy unidade_insert on public.ferramentas_unidade for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)));
drop policy unidade_update on public.ferramentas_unidade;
create policy unidade_update on public.ferramentas_unidade for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)));

drop policy estoque_select on public.estoque_pool;
create policy estoque_select on public.estoque_pool for select to authenticated
  using (private.tem_acesso_filial(filial_id));
drop policy estoque_insert on public.estoque_pool;
create policy estoque_insert on public.estoque_pool for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)));
drop policy estoque_update on public.estoque_pool;
create policy estoque_update on public.estoque_pool for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)));

drop policy emprestimos_select on public.emprestimos;
create policy emprestimos_select on public.emprestimos for select to authenticated
  using (exists (select 1 from public.estoque_pool ep where ep.id = emprestimos.estoque_id and private.tem_acesso_filial(ep.filial_id)));
drop policy emprestimos_update on public.emprestimos;
create policy emprestimos_update on public.emprestimos for update to authenticated
  using (exists (select 1 from public.estoque_pool ep where ep.id = emprestimos.estoque_id and private.tem_acesso_filial(ep.filial_id)))
  with check (exists (select 1 from public.estoque_pool ep where ep.id = emprestimos.estoque_id and private.tem_acesso_filial(ep.filial_id)));

drop policy movimentacoes_select on public.movimentacoes;
create policy movimentacoes_select on public.movimentacoes for select to authenticated
  using (exists (select 1 from public.ferramentas_unidade f where f.id = movimentacoes.ferramenta_id and private.tem_acesso_filial(f.filial_id)));

drop policy manutencoes_select on public.manutencoes;
create policy manutencoes_select on public.manutencoes for select to authenticated
  using (exists (select 1 from public.ferramentas_unidade f where f.id = manutencoes.ferramenta_id and private.tem_acesso_filial(f.filial_id)));
drop policy manutencoes_update on public.manutencoes;
create policy manutencoes_update on public.manutencoes for update to authenticated
  using (exists (select 1 from public.ferramentas_unidade f where f.id = manutencoes.ferramenta_id and private.tem_acesso_filial(f.filial_id)))
  with check (exists (select 1 from public.ferramentas_unidade f where f.id = manutencoes.ferramenta_id and private.tem_acesso_filial(f.filial_id)));

drop policy auditorias_select on public.auditorias_ferramentaria;
create policy auditorias_select on public.auditorias_ferramentaria for select to authenticated
  using (private.tem_acesso_filial(filial_id));
drop policy auditorias_insert on public.auditorias_ferramentaria;
create policy auditorias_insert on public.auditorias_ferramentaria for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)));
drop policy auditorias_update on public.auditorias_ferramentaria;
create policy auditorias_update on public.auditorias_ferramentaria for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and private.tem_acesso_filial(filial_id)));

drop policy auditoria_itens_select on public.auditoria_itens;
create policy auditoria_itens_select on public.auditoria_itens for select to authenticated
  using (exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and private.tem_acesso_filial(a.filial_id)));
drop policy auditoria_itens_insert on public.auditoria_itens;
create policy auditoria_itens_insert on public.auditoria_itens for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and private.tem_acesso_filial(a.filial_id))));
drop policy auditoria_itens_update on public.auditoria_itens;
create policy auditoria_itens_update on public.auditoria_itens for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and private.tem_acesso_filial(a.filial_id))))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and private.tem_acesso_filial(a.filial_id))));

-- ── Mesma troca dentro dos triggers de validação de escrita
--    (BEFORE INSERT/UPDATE — a real "porta de entrada" das ações).
-- ════════════════════════════════════════════════════════════════

create or replace function public.fn_valida_transicao_movimentacao()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_status public.status_ferramenta;
  v_filial uuid;
begin
  select status, filial_id into v_status, v_filial from public.ferramentas_unidade where id = new.ferramenta_id for update;
  if v_status is null then
    raise exception 'Ferramenta não encontrada.';
  end if;
  if not private.is_ativo() then
    raise exception 'Seu usuário está inativo.';
  end if;
  if not private.tem_acesso_filial(v_filial) then
    raise exception 'Você só pode registrar movimentações de ferramentas de filiais que você acessa.';
  end if;

  new.registrado_por := auth.uid();

  case new.tipo
    when 'retirada' then
      if v_status <> 'disponivel' then
        raise exception 'Só é possível retirar uma ferramenta que está disponível (status atual: %).', v_status;
      end if;
      if new.pessoa_responsavel_id is null then
        raise exception 'Informe com quem a ferramenta vai ficar.';
      end if;
    when 'devolucao' then
      if v_status <> 'com_colaborador' then
        raise exception 'Só é possível devolver uma ferramenta que está com um colaborador (status atual: %).', v_status;
      end if;
    when 'envio_afericao' then
      if v_status <> 'disponivel' then
        raise exception 'Só é possível enviar para aferição uma ferramenta disponível (status atual: %). Registre a devolução antes.', v_status;
      end if;
    when 'retorno_afericao' then
      if v_status <> 'em_afericao' then
        raise exception 'Essa ferramenta não está em aferição.';
      end if;
    when 'envio_conserto' then
      if coalesce(current_setting('app.internal_write', true), '') <> 'true' then
        raise exception 'Use a tela de Manutenções para registrar o envio de uma ferramenta para conserto.';
      end if;
      if v_status <> 'disponivel' then
        raise exception 'Só é possível enviar para conserto uma ferramenta disponível (status atual: %).', v_status;
      end if;
    when 'retorno_conserto' then
      if coalesce(current_setting('app.internal_write', true), '') <> 'true' then
        raise exception 'Use a tela de Manutenções para registrar o retorno de uma ferramenta do conserto.';
      end if;
      -- não checa v_status aqui de propósito: quando esta movimentação é
      -- inserida, fn_aplicar_retorno_conserto já atualizou o status da
      -- ferramenta um passo antes (mesmo padrão usado abaixo em 'transferencia').
    when 'transferencia' then
      if coalesce(current_setting('app.internal_write', true), '') <> 'true' then
        raise exception 'Transferências são aplicadas automaticamente na aprovação, não podem ser inseridas diretamente.';
      end if;
    when 'extravio' then
      if v_status in ('extraviada','baixada') then
        raise exception 'Essa ferramenta já está marcada como %.', v_status;
      end if;
    when 'baixa' then
      if coalesce(current_setting('app.internal_write', true), '') <> 'true' and not private.is_admin_area_ou_geral() then
        raise exception 'Só um administrador pode dar baixa em uma ferramenta.';
      end if;
      if v_status = 'baixada' then
        raise exception 'Essa ferramenta já está baixada.';
      end if;
    when 'reativacao' then
      if not private.is_admin_area_ou_geral() then
        raise exception 'Só um administrador pode reativar uma ferramenta.';
      end if;
      if v_status not in ('baixada','extraviada') then
        raise exception 'Essa ferramenta não está baixada nem extraviada.';
      end if;
  end case;

  return new;
end; $function$;

create or replace function public.fn_valida_envio_conserto()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_status public.status_ferramenta; v_filial uuid;
begin
  select status, filial_id into v_status, v_filial from public.ferramentas_unidade where id = new.ferramenta_id for update;
  if v_status is null then raise exception 'Ferramenta não encontrada.'; end if;
  if not private.is_ativo() then raise exception 'Seu usuário está inativo.'; end if;
  if not private.tem_acesso_filial(v_filial) then
    raise exception 'Você só pode registrar conserto de ferramentas de filiais que você acessa.';
  end if;
  if v_status <> 'disponivel' then
    raise exception 'Só é possível enviar para conserto uma ferramenta disponível (status atual: %).', v_status;
  end if;
  new.registrado_por := auth.uid();
  new.status := 'em_conserto';
  return new;
end; $function$;

create or replace function public.fn_valida_retorno_conserto()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_filial uuid;
begin
  if old.status <> 'em_conserto' then
    raise exception 'Esse registro de conserto já foi encerrado.';
  end if;
  select filial_id into v_filial from public.ferramentas_unidade where id = old.ferramenta_id;
  if not private.tem_acesso_filial(v_filial) then
    raise exception 'Você só pode registrar retorno de conserto de ferramentas de filiais que você acessa.';
  end if;
  if new.status not in ('concluido','baixada') then
    raise exception 'Status de retorno inválido.';
  end if;
  if new.status = 'baixada' and not private.is_admin_area_ou_geral() then
    raise exception 'Só um administrador pode dar baixa em uma ferramenta que não teve conserto bem-sucedido.';
  end if;
  if new.data_retorno_real is null then
    new.data_retorno_real := current_date;
  end if;
  return new;
end; $function$;

create or replace function public.fn_valida_emprestimo()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_filial uuid;
  v_total integer;
  v_emprestado integer;
begin
  select filial_id, quantidade_total into v_filial, v_total from public.estoque_pool where id = new.estoque_id for update;
  if v_filial is null then
    raise exception 'Estoque não encontrado.';
  end if;
  if not private.is_ativo() then
    raise exception 'Seu usuário está inativo.';
  end if;
  if not private.tem_acesso_filial(v_filial) then
    raise exception 'Você só pode registrar retirada de ferramentas de filiais que você acessa.';
  end if;
  select coalesce(sum(quantidade),0) into v_emprestado from public.emprestimos where estoque_id = new.estoque_id and data_devolucao is null;
  if new.quantidade > (v_total - v_emprestado) then
    raise exception 'Não há saldo suficiente nesse estoque (disponível: %).', (v_total - v_emprestado);
  end if;
  new.registrado_por := auth.uid();
  return new;
end; $function$;

create or replace function public.fn_valida_devolucao_emprestimo()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_filial uuid;
begin
  if old.data_devolucao is not null then
    raise exception 'Este empréstimo já foi devolvido.';
  end if;
  select filial_id into v_filial from public.estoque_pool where id = old.estoque_id;
  if not private.tem_acesso_filial(v_filial) then
    raise exception 'Você só pode devolver ferramentas de filiais que você acessa.';
  end if;
  if new.data_devolucao is null then
    new.data_devolucao := now();
  end if;
  return new;
end; $function$;

-- ════════════════════════════════════════════════════════════════
-- Transferências entre filiais (só ferramentas_unidade — pool
-- continua sendo ajustado manualmente pelo admin, como já era).
-- ════════════════════════════════════════════════════════════════

create type public.status_transferencia as enum ('pendente','aprovada','rejeitada','cancelada');

create table public.transferencias_ferramenta (
  id uuid primary key default gen_random_uuid(),
  ferramenta_id uuid not null references public.ferramentas_unidade(id),
  filial_origem_id uuid not null references public.filiais(id),
  filial_destino_id uuid not null references public.filiais(id),
  solicitante_id uuid not null references public.profiles(id),
  status public.status_transferencia not null default 'pendente',
  aprovador_id uuid references public.profiles(id),
  motivo text,
  resposta text,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
alter table public.transferencias_ferramenta enable row level security;

create policy transferencias_select on public.transferencias_ferramenta for select to authenticated
  using (private.is_admin_geral() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));
create policy transferencias_insert on public.transferencias_ferramenta for insert to authenticated
  with check (private.is_ativo());
create policy transferencias_update on public.transferencias_ferramenta for update to authenticated
  using (private.is_admin_geral() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id))
  with check (private.is_admin_geral() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));
revoke delete on public.transferencias_ferramenta from authenticated;
revoke update on public.transferencias_ferramenta from authenticated;
grant update (status, resposta) on public.transferencias_ferramenta to authenticated;

create or replace function public.fn_valida_transferencia_solicitacao()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_status public.status_ferramenta; v_filial_atual uuid;
begin
  select status, filial_id into v_status, v_filial_atual from public.ferramentas_unidade where id = new.ferramenta_id for update;
  if v_filial_atual is null then raise exception 'Ferramenta não encontrada.'; end if;
  if not private.is_ativo() then raise exception 'Seu usuário está inativo.'; end if;
  if v_status <> 'disponivel' then
    raise exception 'Só é possível transferir uma ferramenta disponível (status atual: %).', v_status;
  end if;
  new.filial_origem_id := v_filial_atual;
  if new.filial_destino_id is null or new.filial_destino_id = v_filial_atual then
    raise exception 'Selecione uma filial de destino diferente da atual.';
  end if;
  if not private.tem_acesso_filial(v_filial_atual) or not private.tem_acesso_filial(new.filial_destino_id) then
    raise exception 'Você só pode solicitar transferência entre filiais que você acessa.';
  end if;
  new.solicitante_id := auth.uid();
  new.status := 'pendente';
  new.aprovador_id := null;
  new.decided_at := null;
  return new;
end; $function$;

create or replace function public.fn_aplicar_transferencia_solicitacao()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  update public.ferramentas_unidade set status = 'em_transferencia' where id = new.ferramenta_id;
  return new;
end; $function$;

create or replace function public.fn_notificar_transferencia_solicitada()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'transferencia_solicitada', 'Nova solicitação de transferência',
    'Uma transferência de ferramenta para ' || (select nome from public.filiais where id = new.filial_destino_id) || ' aguarda sua aprovação.',
    new.id
  from public.profiles p
  where p.user_type = 'admin_area' and p.filial_id = new.filial_destino_id and p.is_active;
  return new;
end; $function$;

create or replace function public.fn_valida_transferencia_decisao()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_is_gestor_destino boolean;
begin
  if old.status <> 'pendente' then
    raise exception 'Essa solicitação já foi decidida.';
  end if;
  if new.status = 'cancelada' then
    if auth.uid() <> old.solicitante_id and not private.is_admin_geral() then
      raise exception 'Só quem solicitou pode cancelar essa transferência.';
    end if;
  elsif new.status in ('aprovada','rejeitada') then
    select exists(
      select 1 from public.profiles
      where id = auth.uid() and user_type = 'admin_area' and filial_id = old.filial_destino_id
    ) into v_is_gestor_destino;
    if not private.is_admin_geral() and not v_is_gestor_destino then
      raise exception 'Só o gestor da filial de destino (ou um administrador geral) pode aprovar ou rejeitar essa transferência.';
    end if;
    new.aprovador_id := auth.uid();
  else
    raise exception 'Status de decisão inválido.';
  end if;
  new.decided_at := now();
  return new;
end; $function$;

create or replace function public.fn_aplicar_transferencia_decisao()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if new.status = 'aprovada' then
    perform set_config('app.internal_write','true', true);
    update public.ferramentas_unidade
      set filial_id = new.filial_destino_id, status = 'disponivel'
      where id = new.ferramenta_id;
    insert into public.movimentacoes(ferramenta_id, tipo, registrado_por, observacao)
      values (new.ferramenta_id, 'transferencia', auth.uid(),
        'Transferida de ' || (select nome from public.filiais where id = new.filial_origem_id) ||
        ' para ' || (select nome from public.filiais where id = new.filial_destino_id) ||
        coalesce('. Motivo: ' || new.motivo, ''));
    perform set_config('app.internal_write','false', true);
  elsif new.status in ('rejeitada','cancelada') then
    update public.ferramentas_unidade set status = 'disponivel' where id = new.ferramenta_id;
  end if;

  if new.status in ('aprovada','rejeitada') then
    insert into public.notifications (user_id, type, title, body, related_id)
    values (new.solicitante_id,
      'transferencia_decidida',
      case when new.status = 'aprovada' then 'Transferência aprovada' else 'Transferência rejeitada' end,
      'Sua solicitação de transferência foi ' || case when new.status = 'aprovada' then 'aprovada.' else 'rejeitada.' end,
      new.id);
  end if;
  return new;
end; $function$;

create trigger trg_valida_transferencia_solicitacao before insert on public.transferencias_ferramenta
  for each row execute function public.fn_valida_transferencia_solicitacao();
create trigger trg_aplicar_transferencia_solicitacao after insert on public.transferencias_ferramenta
  for each row execute function public.fn_aplicar_transferencia_solicitacao();
create trigger trg_notificar_transferencia_solicitada after insert on public.transferencias_ferramenta
  for each row execute function public.fn_notificar_transferencia_solicitada();
create trigger trg_valida_transferencia_decisao before update on public.transferencias_ferramenta
  for each row execute function public.fn_valida_transferencia_decisao();
create trigger trg_aplicar_transferencia_decisao after update on public.transferencias_ferramenta
  for each row execute function public.fn_aplicar_transferencia_decisao();

alter publication supabase_realtime add table public.transferencias_ferramenta;
