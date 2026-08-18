-- Novo modelo de transferência entre filiais: qualquer pessoa pode solicitar transferência
-- de uma ferramenta/estoque que ela acessa pra QUALQUER outra filial (não precisa mais ter
-- acesso à filial de destino) — e toda decisão (aprovar/rejeitar) passa a ser exclusiva do
-- Gerente de Pós-Vendas (novo flag no perfil), não mais do gestor local da filial de destino.

alter table public.profiles add column gerente_pos_vendas boolean not null default false;

create or replace function private.is_gerente_pos_vendas()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select gerente_pos_vendas from public.profiles where id = auth.uid()), false);
$$;
grant execute on function private.is_gerente_pos_vendas() to authenticated;

-- ══ FERRAMENTA INDIVIDUAL ══

-- solicitação: só precisa acesso à filial de ORIGEM (a ferramenta em si já garante isso);
-- destino pode ser qualquer filial.
create or replace function public.fn_valida_transferencia_solicitacao()
returns trigger language plpgsql security definer set search_path = '' as $$
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
  if not private.tem_acesso_filial(v_filial_atual) then
    raise exception 'Você só pode solicitar transferência de uma ferramenta que você acessa.';
  end if;
  new.solicitante_id := auth.uid();
  new.status := 'pendente';
  new.aprovador_id := null;
  new.decided_at := null;
  return new;
end; $$;

-- decisão: só o Gerente de Pós-Vendas (ou admin_geral) aprova/rejeita; cancelar continua só o solicitante
create or replace function public.fn_valida_transferencia_decisao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'pendente' then
    raise exception 'Essa solicitação já foi decidida.';
  end if;
  if new.status = 'cancelada' then
    if auth.uid() <> old.solicitante_id and not private.is_admin_geral() then
      raise exception 'Só quem solicitou pode cancelar essa transferência.';
    end if;
  elsif new.status in ('aprovada','rejeitada') then
    if not private.is_admin_geral() and not private.is_gerente_pos_vendas() then
      raise exception 'Só o Gerente de Pós-Vendas (ou um administrador geral) pode aprovar ou rejeitar essa transferência.';
    end if;
    new.aprovador_id := auth.uid();
  else
    raise exception 'Status de decisão inválido.';
  end if;
  new.decided_at := now();
  return new;
end; $$;

-- notifica o(s) Gerente(s) de Pós-Vendas em vez do gestor local da filial de destino
create or replace function public.fn_notificar_transferencia_solicitada()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'transferencia_solicitada', 'Nova solicitação de transferência',
    'Uma transferência de ferramenta para ' || (select nome from public.filiais where id = new.filial_destino_id) || ' aguarda sua aprovação.',
    new.id
  from public.profiles p
  where p.gerente_pos_vendas and p.is_active;
  return new;
end; $$;

-- RLS: o Gerente de Pós-Vendas enxerga e decide todas as transferências, mesmo de filiais que não acessa
drop policy if exists transferencias_select on public.transferencias_ferramenta;
create policy transferencias_select on public.transferencias_ferramenta for select
  using (private.is_admin_geral() or private.is_gerente_pos_vendas() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));
drop policy if exists transferencias_update on public.transferencias_ferramenta;
create policy transferencias_update on public.transferencias_ferramenta for update
  using (private.is_admin_geral() or private.is_gerente_pos_vendas() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id))
  with check (private.is_admin_geral() or private.is_gerente_pos_vendas() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));

-- ══ ESTOQUE POR QUANTIDADE ══

create or replace function public.fn_valida_transferencia_estoque_solicitacao()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_qtd_total integer; v_emprestado integer; v_disponivel integer;
begin
  if not private.is_ativo() then raise exception 'Seu usuário está inativo.'; end if;
  if new.filial_destino_id is null or new.filial_destino_id = new.filial_origem_id then
    raise exception 'Selecione uma filial de destino diferente da origem.';
  end if;
  if not private.tem_acesso_filial(new.filial_origem_id) then
    raise exception 'Você só pode solicitar transferência de um estoque que você acessa.';
  end if;

  select quantidade_total into v_qtd_total from public.estoque_pool
    where catalogo_id = new.catalogo_id and filial_id = new.filial_origem_id for update;
  if v_qtd_total is null then
    raise exception 'Não há estoque desse tipo na filial de origem.';
  end if;
  select coalesce(sum(e.quantidade),0) into v_emprestado
    from public.emprestimos e join public.estoque_pool p on p.id = e.estoque_id
    where p.catalogo_id = new.catalogo_id and p.filial_id = new.filial_origem_id and e.data_devolucao is null;
  v_disponivel := v_qtd_total - v_emprestado;
  if new.quantidade > v_disponivel then
    raise exception 'Só há % unidade(s) disponível(is) pra transferir (o restante está emprestado).', v_disponivel;
  end if;

  new.solicitante_id := auth.uid();
  new.status := 'pendente';
  new.aprovador_id := null;
  new.decided_at := null;
  return new;
end; $$;

create or replace function public.fn_valida_transferencia_estoque_decisao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'pendente' then
    raise exception 'Essa solicitação já foi decidida.';
  end if;
  if new.status = 'cancelada' then
    if auth.uid() <> old.solicitante_id and not private.is_admin_geral() then
      raise exception 'Só quem solicitou pode cancelar essa transferência.';
    end if;
  elsif new.status in ('aprovada','rejeitada') then
    if not private.is_admin_geral() and not private.is_gerente_pos_vendas() then
      raise exception 'Só o Gerente de Pós-Vendas (ou um administrador geral) pode aprovar ou rejeitar essa transferência.';
    end if;
    new.aprovador_id := auth.uid();
  else
    raise exception 'Status de decisão inválido.';
  end if;
  new.decided_at := now();
  return new;
end; $$;

create or replace function public.fn_notificar_transferencia_estoque_solicitada()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'transferencia_estoque_solicitada', 'Nova solicitação de transferência de estoque',
    'Uma transferência de estoque para ' || (select nome from public.filiais where id = new.filial_destino_id) || ' aguarda sua aprovação.',
    new.id
  from public.profiles p
  where p.gerente_pos_vendas and p.is_active;
  return new;
end; $$;

drop policy if exists transferencias_estoque_select on public.transferencias_estoque;
create policy transferencias_estoque_select on public.transferencias_estoque for select
  using (private.is_admin_geral() or private.is_gerente_pos_vendas() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));
drop policy if exists transferencias_estoque_update on public.transferencias_estoque;
create policy transferencias_estoque_update on public.transferencias_estoque for update
  using (private.is_admin_geral() or private.is_gerente_pos_vendas() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id))
  with check (private.is_admin_geral() or private.is_gerente_pos_vendas() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));
