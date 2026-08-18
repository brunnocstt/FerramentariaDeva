-- Transferência de estoque por quantidade (pool) entre filiais — mesmo padrão já usado
-- em transferencias_ferramenta (ferramentas com código individual), reaproveitando o
-- enum public.status_transferencia. A quantidade solicitada é descontada da origem
-- imediatamente (reservada) na solicitação, e só chega no destino quando aprovada;
-- se rejeitada/cancelada, volta pra origem.

create table public.transferencias_estoque (
  id uuid primary key default gen_random_uuid(),
  catalogo_id uuid not null references public.ferramentas_catalogo(id),
  filial_origem_id uuid not null references public.filiais(id),
  filial_destino_id uuid not null references public.filiais(id),
  quantidade integer not null check (quantidade > 0),
  solicitante_id uuid not null references public.profiles(id),
  status public.status_transferencia not null default 'pendente',
  aprovador_id uuid references public.profiles(id),
  motivo text,
  resposta text,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
alter table public.transferencias_estoque enable row level security;

create policy transferencias_estoque_select on public.transferencias_estoque for select
  using (private.is_admin_geral() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));
create policy transferencias_estoque_insert on public.transferencias_estoque for insert
  with check (private.is_ativo());
create policy transferencias_estoque_update on public.transferencias_estoque for update
  using (private.is_admin_geral() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id))
  with check (private.is_admin_geral() or private.tem_acesso_filial(filial_origem_id) or private.tem_acesso_filial(filial_destino_id));

-- valida e monta a solicitação
create or replace function public.fn_valida_transferencia_estoque_solicitacao()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_qtd_total integer; v_emprestado integer; v_disponivel integer;
begin
  if not private.is_ativo() then raise exception 'Seu usuário está inativo.'; end if;
  if new.filial_destino_id is null or new.filial_destino_id = new.filial_origem_id then
    raise exception 'Selecione uma filial de destino diferente da origem.';
  end if;
  if not private.tem_acesso_filial(new.filial_origem_id) or not private.tem_acesso_filial(new.filial_destino_id) then
    raise exception 'Você só pode solicitar transferência entre filiais que você acessa.';
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

-- reserva a quantidade na origem assim que a solicitação é criada
create or replace function public.fn_aplicar_transferencia_estoque_solicitacao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.estoque_pool set quantidade_total = quantidade_total - new.quantidade
    where catalogo_id = new.catalogo_id and filial_id = new.filial_origem_id;
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
  where p.user_type = 'admin_area' and p.filial_id = new.filial_destino_id and p.is_active;
  return new;
end; $$;

-- só o gestor da filial de destino (ou admin_geral) aprova/rejeita; só o solicitante cancela
create or replace function public.fn_valida_transferencia_estoque_decisao()
returns trigger language plpgsql security definer set search_path = '' as $$
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
end; $$;

-- aprovada: soma no destino (cria a linha de estoque se não existir); rejeitada/cancelada: devolve pra origem
create or replace function public.fn_aplicar_transferencia_estoque_decisao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'aprovada' then
    insert into public.estoque_pool (catalogo_id, filial_id, quantidade_total)
      values (new.catalogo_id, new.filial_destino_id, new.quantidade)
    on conflict (catalogo_id, filial_id) do update
      set quantidade_total = public.estoque_pool.quantidade_total + excluded.quantidade_total;
  elsif new.status in ('rejeitada','cancelada') then
    update public.estoque_pool set quantidade_total = quantidade_total + new.quantidade
      where catalogo_id = new.catalogo_id and filial_id = new.filial_origem_id;
  end if;

  if new.status in ('aprovada','rejeitada') then
    insert into public.notifications (user_id, type, title, body, related_id)
    values (new.solicitante_id,
      'transferencia_estoque_decidida',
      case when new.status = 'aprovada' then 'Transferência de estoque aprovada' else 'Transferência de estoque rejeitada' end,
      'Sua solicitação de transferência de estoque foi ' || case when new.status = 'aprovada' then 'aprovada.' else 'rejeitada.' end,
      new.id);
  end if;
  return new;
end; $$;

create trigger trg_valida_transferencia_estoque_solicitacao before insert on public.transferencias_estoque
  for each row execute function public.fn_valida_transferencia_estoque_solicitacao();
create trigger trg_aplicar_transferencia_estoque_solicitacao after insert on public.transferencias_estoque
  for each row execute function public.fn_aplicar_transferencia_estoque_solicitacao();
create trigger trg_notificar_transferencia_estoque_solicitada after insert on public.transferencias_estoque
  for each row execute function public.fn_notificar_transferencia_estoque_solicitada();
create trigger trg_valida_transferencia_estoque_decisao before update on public.transferencias_estoque
  for each row execute function public.fn_valida_transferencia_estoque_decisao();
create trigger trg_aplicar_transferencia_estoque_decisao after update on public.transferencias_estoque
  for each row execute function public.fn_aplicar_transferencia_estoque_decisao();

alter publication supabase_realtime add table public.transferencias_estoque;
