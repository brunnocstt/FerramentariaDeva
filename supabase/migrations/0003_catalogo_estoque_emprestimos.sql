-- ════════════════════════════════════════════════════════════════
-- Catálogo de ferramentas (global) × Estoque por filial × Empréstimos
-- por matrícula (pool) + matrícula em profiles
-- ════════════════════════════════════════════════════════════════

-- ── categorias_ferramenta: controle individual vs pool ──────────
alter table public.categorias_ferramenta add column controle_individual boolean not null default true;
alter table public.categorias_ferramenta add constraint chk_afericao_exige_individual
  check (not (requer_afericao and not controle_individual));

-- ── profiles: matrícula do crachá ─────────────────────────────
alter table public.profiles add column matricula text unique;

-- ── ferramentas_catalogo: "o que é a ferramenta", sem filial ──
create table public.ferramentas_catalogo (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  categoria_id uuid references public.categorias_ferramenta(id),
  codigo_interno text,
  observacoes text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.ferramentas_catalogo enable row level security;
create trigger trg_catalogo_upd before update on public.ferramentas_catalogo
  for each row execute function public.fn_set_updated_at();
create policy catalogo_select on public.ferramentas_catalogo for select to authenticated using (true);
create policy catalogo_write on public.ferramentas_catalogo for all to authenticated
  using (private.is_admin_geral()) with check (private.is_admin_geral());

-- ── ferramentas_unidade: substitui "ferramentas" — unidades físicas individuais, por filial ──
create table public.ferramentas_unidade (
  id uuid primary key default gen_random_uuid(),
  catalogo_id uuid not null references public.ferramentas_catalogo(id),
  filial_id uuid not null references public.filiais(id),
  codigo text not null,
  status public.status_ferramenta not null default 'disponivel',
  colaborador_atual_id uuid references public.profiles(id),
  data_retirada_atual timestamptz,
  data_ultima_afericao date,
  data_proxima_afericao date,
  data_saida_afericao date,
  data_retorno_afericao date,
  observacoes text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(filial_id, codigo)
);
alter table public.ferramentas_unidade enable row level security;
create trigger trg_unidade_upd before update on public.ferramentas_unidade
  for each row execute function public.fn_set_updated_at();

-- ── repontar FKs de movimentacoes/manutencoes/auditoria_itens e dropar a tabela antiga ──
-- CASCADE derruba também as policies de movimentacoes/manutencoes que referenciavam
-- "ferramentas" (movimentacoes_select, manutencoes_select, manutencoes_update) — recriadas
-- logo abaixo, já apontando pra ferramentas_unidade.
alter table public.movimentacoes drop constraint movimentacoes_ferramenta_id_fkey;
alter table public.manutencoes drop constraint manutencoes_ferramenta_id_fkey;
alter table public.auditoria_itens drop constraint auditoria_itens_ferramenta_id_fkey;
drop table public.ferramentas cascade;
alter table public.movimentacoes add constraint movimentacoes_ferramenta_id_fkey
  foreign key (ferramenta_id) references public.ferramentas_unidade(id);
alter table public.manutencoes add constraint manutencoes_ferramenta_id_fkey
  foreign key (ferramenta_id) references public.ferramentas_unidade(id);
alter table public.auditoria_itens add constraint auditoria_itens_ferramenta_id_fkey
  foreign key (ferramenta_id) references public.ferramentas_unidade(id);

create policy movimentacoes_select on public.movimentacoes for select to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.ferramentas_unidade f where f.id = movimentacoes.ferramenta_id and f.filial_id = private.my_filial_id()));
create policy manutencoes_select on public.manutencoes for select to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.ferramentas_unidade f where f.id = manutencoes.ferramenta_id and f.filial_id = private.my_filial_id()));
create policy manutencoes_update on public.manutencoes for update to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.ferramentas_unidade f where f.id = manutencoes.ferramenta_id and f.filial_id = private.my_filial_id()))
  with check (private.is_admin_geral() or exists (select 1 from public.ferramentas_unidade f where f.id = manutencoes.ferramenta_id and f.filial_id = private.my_filial_id()));

-- ── redefine as funções de trigger apontando pra ferramentas_unidade ──
-- (mesma lógica de antes, só troca a tabela; fn_aplicar_movimentacao ganha o controle de
-- data_retirada_atual, usado pro painel "há quanto tempo está com o colaborador")

create or replace function public.fn_valida_transicao_movimentacao()
returns trigger language plpgsql security definer set search_path = '' as $$
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
  if not private.is_admin_geral() and v_filial is distinct from private.my_filial_id() then
    raise exception 'Você só pode registrar movimentações de ferramentas da sua própria filial.';
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
      if v_status <> 'em_conserto' then
        raise exception 'Essa ferramenta não está em conserto.';
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
end; $$;

create or replace function public.fn_aplicar_movimentacao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  case new.tipo
    when 'retirada' then
      update public.ferramentas_unidade set status='com_colaborador', colaborador_atual_id=new.pessoa_responsavel_id,
        data_retirada_atual=new.data where id=new.ferramenta_id;
    when 'devolucao' then
      update public.ferramentas_unidade set status='disponivel', colaborador_atual_id=null, data_retirada_atual=null where id=new.ferramenta_id;
    when 'envio_afericao' then
      update public.ferramentas_unidade set status='em_afericao', data_saida_afericao=new.data::date where id=new.ferramenta_id;
    when 'retorno_afericao' then
      update public.ferramentas_unidade set status='disponivel', data_retorno_afericao=new.data::date,
        data_ultima_afericao=new.data::date, data_proxima_afericao=(new.data::date + interval '1 year')::date
        where id=new.ferramenta_id;
    when 'envio_conserto' then
      update public.ferramentas_unidade set status='em_conserto' where id=new.ferramenta_id;
    when 'retorno_conserto' then
      update public.ferramentas_unidade set status='disponivel' where id=new.ferramenta_id;
    when 'extravio' then
      update public.ferramentas_unidade set status='extraviada', colaborador_atual_id=null, data_retirada_atual=null where id=new.ferramenta_id;
    when 'baixa' then
      update public.ferramentas_unidade set status='baixada', ativo=false, colaborador_atual_id=null, data_retirada_atual=null where id=new.ferramenta_id;
    when 'reativacao' then
      update public.ferramentas_unidade set status='disponivel', ativo=true where id=new.ferramenta_id;
  end case;
  return new;
end; $$;

create or replace function public.fn_valida_envio_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_status public.status_ferramenta; v_filial uuid;
begin
  select status, filial_id into v_status, v_filial from public.ferramentas_unidade where id = new.ferramenta_id for update;
  if v_status is null then raise exception 'Ferramenta não encontrada.'; end if;
  if not private.is_ativo() then raise exception 'Seu usuário está inativo.'; end if;
  if not private.is_admin_geral() and v_filial is distinct from private.my_filial_id() then
    raise exception 'Você só pode registrar conserto de ferramentas da sua própria filial.';
  end if;
  if v_status <> 'disponivel' then
    raise exception 'Só é possível enviar para conserto uma ferramenta disponível (status atual: %).', v_status;
  end if;
  new.registrado_por := auth.uid();
  new.status := 'em_conserto';
  return new;
end; $$;

create or replace function public.fn_aplicar_envio_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.ferramentas_unidade set status='em_conserto' where id = new.ferramenta_id;
  perform set_config('app.internal_write','true', true);
  insert into public.movimentacoes(ferramenta_id, tipo, registrado_por, observacao)
    values (new.ferramenta_id, 'envio_conserto', new.registrado_por, new.motivo);
  perform set_config('app.internal_write','false', true);
  return new;
end; $$;

create or replace function public.fn_valida_retorno_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_filial uuid;
begin
  if old.status <> 'em_conserto' then
    raise exception 'Esse registro de conserto já foi encerrado.';
  end if;
  select filial_id into v_filial from public.ferramentas_unidade where id = old.ferramenta_id;
  if not private.is_admin_geral() and v_filial is distinct from private.my_filial_id() then
    raise exception 'Você só pode registrar retorno de conserto de ferramentas da sua própria filial.';
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
end; $$;

create or replace function public.fn_aplicar_retorno_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('app.internal_write','true', true);
  if new.status = 'concluido' then
    update public.ferramentas_unidade set status='disponivel' where id = new.ferramenta_id;
    insert into public.movimentacoes(ferramenta_id, tipo, registrado_por, observacao)
      values (new.ferramenta_id, 'retorno_conserto', auth.uid(), new.observacoes);
  else
    update public.ferramentas_unidade set status='baixada', ativo=false, colaborador_atual_id=null, data_retirada_atual=null where id = new.ferramenta_id;
    insert into public.movimentacoes(ferramenta_id, tipo, registrado_por, observacao)
      values (new.ferramenta_id, 'baixa', auth.uid(), coalesce(new.observacoes,'Baixada após conserto sem sucesso.'));
  end if;
  perform set_config('app.internal_write','false', true);
  return new;
end; $$;

-- ── RLS: ferramentas_unidade (mesmo padrão da antiga ferramentas) ──
create policy unidade_select on public.ferramentas_unidade for select to authenticated
  using (private.is_admin_geral() or filial_id = private.my_filial_id());
create policy unidade_insert on public.ferramentas_unidade for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));
create policy unidade_update on public.ferramentas_unidade for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));
revoke update on public.ferramentas_unidade from authenticated;
grant update (codigo, observacoes) on public.ferramentas_unidade to authenticated;

-- ── estoque_pool: quantidade total de um tipo, por filial ──────
create table public.estoque_pool (
  id uuid primary key default gen_random_uuid(),
  catalogo_id uuid not null references public.ferramentas_catalogo(id),
  filial_id uuid not null references public.filiais(id),
  quantidade_total integer not null default 0 check (quantidade_total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(catalogo_id, filial_id)
);
alter table public.estoque_pool enable row level security;
create trigger trg_estoque_upd before update on public.estoque_pool
  for each row execute function public.fn_set_updated_at();
create policy estoque_select on public.estoque_pool for select to authenticated
  using (private.is_admin_geral() or filial_id = private.my_filial_id());
create policy estoque_insert on public.estoque_pool for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));
create policy estoque_update on public.estoque_pool for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));

-- ── emprestimos: retiradas/devoluções de ferramentas em pool ────
create table public.emprestimos (
  id uuid primary key default gen_random_uuid(),
  estoque_id uuid not null references public.estoque_pool(id),
  colaborador_id uuid not null references public.profiles(id),
  quantidade integer not null default 1 check (quantidade > 0),
  data_retirada timestamptz not null default now(),
  data_devolucao timestamptz,
  registrado_por uuid references public.profiles(id),
  observacao text,
  created_at timestamptz not null default now()
);
alter table public.emprestimos enable row level security;

create or replace function public.fn_valida_emprestimo()
returns trigger language plpgsql security definer set search_path = '' as $$
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
  if not private.is_admin_geral() and v_filial is distinct from private.my_filial_id() then
    raise exception 'Você só pode registrar retirada de ferramentas da sua própria filial.';
  end if;
  select coalesce(sum(quantidade),0) into v_emprestado from public.emprestimos where estoque_id = new.estoque_id and data_devolucao is null;
  if new.quantidade > (v_total - v_emprestado) then
    raise exception 'Não há saldo suficiente nesse estoque (disponível: %).', (v_total - v_emprestado);
  end if;
  new.registrado_por := auth.uid();
  return new;
end; $$;
create trigger trg_valida_emprestimo before insert on public.emprestimos
  for each row execute function public.fn_valida_emprestimo();

create or replace function public.fn_valida_devolucao_emprestimo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_filial uuid;
begin
  if old.data_devolucao is not null then
    raise exception 'Este empréstimo já foi devolvido.';
  end if;
  select filial_id into v_filial from public.estoque_pool where id = old.estoque_id;
  if not private.is_admin_geral() and v_filial is distinct from private.my_filial_id() then
    raise exception 'Você só pode devolver ferramentas da sua própria filial.';
  end if;
  if new.data_devolucao is null then
    new.data_devolucao := now();
  end if;
  return new;
end; $$;
create trigger trg_valida_devolucao_emprestimo before update on public.emprestimos
  for each row when (old.data_devolucao is null and new.data_devolucao is distinct from old.data_devolucao)
  execute function public.fn_valida_devolucao_emprestimo();

create policy emprestimos_select on public.emprestimos for select to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.estoque_pool ep where ep.id = emprestimos.estoque_id and ep.filial_id = private.my_filial_id()));
create policy emprestimos_insert on public.emprestimos for insert to authenticated
  with check (private.is_ativo());
create policy emprestimos_update on public.emprestimos for update to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.estoque_pool ep where ep.id = emprestimos.estoque_id and ep.filial_id = private.my_filial_id()))
  with check (private.is_admin_geral() or exists (select 1 from public.estoque_pool ep where ep.id = emprestimos.estoque_id and ep.filial_id = private.my_filial_id()));
revoke update on public.emprestimos from authenticated;
grant update (data_devolucao, observacao) on public.emprestimos to authenticated;
revoke delete on public.emprestimos from authenticated;

-- ── Realtime: publica mudanças pro painel "Ferramentas em Uso" ──
alter publication supabase_realtime add table public.movimentacoes;
alter publication supabase_realtime add table public.emprestimos;
alter publication supabase_realtime add table public.ferramentas_unidade;
