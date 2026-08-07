-- ════════════════════════════════════════════════════════════════
-- Controle de Ferramentaria — Schema completo
-- Aplicar via apply_migration (pode ser dividido em partes menores
-- se algum passo falhar isoladamente).
-- ════════════════════════════════════════════════════════════════

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ── ENUMS ──────────────────────────────────────────────────────
create type public.user_type as enum ('admin_geral','admin_area','colaborador');
create type public.status_ferramenta as enum ('disponivel','com_colaborador','em_afericao','em_conserto','extraviada','baixada');
create type public.tipo_movimentacao as enum ('retirada','devolucao','envio_afericao','retorno_afericao','envio_conserto','retorno_conserto','extravio','baixa','reativacao');
create type public.status_auditoria as enum ('nao_iniciada','em_andamento','concluida');
create type public.resultado_item_auditoria as enum ('encontrada','nao_encontrada','danificada');
create type public.status_manutencao as enum ('em_conserto','concluido','baixada');

-- ── TABELAS ────────────────────────────────────────────────────
create table public.filiais (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  user_type public.user_type not null default 'colaborador',
  filial_id uuid references public.filiais(id),
  is_active boolean not null default true,
  initials char(2),
  color text default '#1955FF',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_filial_admin_geral check (
    (user_type = 'admin_geral' and filial_id is null) or (user_type <> 'admin_geral' and filial_id is not null)
  )
);

create table public.ferramentas (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,
  nome text not null,
  categoria text,
  filial_id uuid not null references public.filiais(id),
  status public.status_ferramenta not null default 'disponivel',
  colaborador_atual_id uuid references public.profiles(id),
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

create table public.movimentacoes (
  id uuid primary key default gen_random_uuid(),
  ferramenta_id uuid not null references public.ferramentas(id),
  tipo public.tipo_movimentacao not null,
  data timestamptz not null default now(),
  registrado_por uuid references public.profiles(id),
  pessoa_responsavel_id uuid references public.profiles(id),
  observacao text,
  created_at timestamptz not null default now()
);

create table public.manutencoes (
  id uuid primary key default gen_random_uuid(),
  ferramenta_id uuid not null references public.ferramentas(id),
  data_envio date not null default current_date,
  motivo text not null,
  local_fornecedor text,
  data_retorno_prevista date,
  data_retorno_real date,
  status public.status_manutencao not null default 'em_conserto',
  observacoes text,
  registrado_por uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.auditorias_ferramentaria (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  filial_id uuid not null references public.filiais(id),
  status public.status_auditoria not null default 'nao_iniciada',
  auditor_id uuid not null references public.profiles(id),
  data_inicio timestamptz,
  data_conclusao timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.auditoria_itens (
  id uuid primary key default gen_random_uuid(),
  auditoria_id uuid not null references public.auditorias_ferramentaria(id) on delete cascade,
  ferramenta_id uuid not null references public.ferramentas(id),
  ferramenta_codigo text not null,
  ferramenta_nome text not null,
  resultado public.resultado_item_auditoria,
  observacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(auditoria_id, ferramenta_id)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  type text not null,
  title text not null,
  body text,
  related_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.password_reset_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

-- ── HELPERS DE RLS (schema private, SECURITY DEFINER) ─────────
create or replace function private.my_user_type()
returns public.user_type language sql stable security definer set search_path = '' as $$
  select user_type from public.profiles where id = auth.uid();
$$;

create or replace function private.my_filial_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select filial_id from public.profiles where id = auth.uid();
$$;

create or replace function private.is_admin_geral()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select user_type = 'admin_geral' from public.profiles where id = auth.uid()), false);
$$;

create or replace function private.is_admin_area_ou_geral()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select user_type in ('admin_geral','admin_area') from public.profiles where id = auth.uid()), false);
$$;

create or replace function private.is_ativo()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select is_active from public.profiles where id = auth.uid()), false);
$$;

grant execute on function private.my_user_type() to authenticated;
grant execute on function private.my_filial_id() to authenticated;
grant execute on function private.is_admin_geral() to authenticated;
grant execute on function private.is_admin_area_ou_geral() to authenticated;
grant execute on function private.is_ativo() to authenticated;

-- ── updated_at genérico ─────────────────────────────────────────
create or replace function public.fn_set_updated_at()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end; $$;

create trigger trg_profiles_upd before update on public.profiles for each row execute function public.fn_set_updated_at();
create trigger trg_ferramentas_upd before update on public.ferramentas for each row execute function public.fn_set_updated_at();
create trigger trg_manutencoes_upd before update on public.manutencoes for each row execute function public.fn_set_updated_at();
create trigger trg_auditorias_upd before update on public.auditorias_ferramentaria for each row execute function public.fn_set_updated_at();
create trigger trg_auditoria_itens_upd before update on public.auditoria_itens for each row execute function public.fn_set_updated_at();

-- ── PROTEÇÕES DE PROFILES (Camada 1) ───────────────────────────
create or replace function public.fn_prevent_self_privilege_escalation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.id = auth.uid() and not private.is_admin_geral() then
    if new.user_type is distinct from old.user_type
       or new.filial_id is distinct from old.filial_id
       or new.is_active is distinct from old.is_active then
      raise exception 'Você não pode alterar seu próprio tipo de usuário, filial ou status de ativo.';
    end if;
  end if;
  return new;
end; $$;
create trigger trg_prevent_self_privilege_escalation before update on public.profiles
  for each row execute function public.fn_prevent_self_privilege_escalation();

create or replace function public.fn_prevent_deactivate_protected_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.email = 'bruno.cesar@deva.com.br' and new.is_active = false then
    raise exception 'Este usuário está protegido e não pode ser desativado.';
  end if;
  return new;
end; $$;
create trigger trg_prevent_deactivate_protected_user before update on public.profiles
  for each row execute function public.fn_prevent_deactivate_protected_user();

create or replace function public.fn_validate_admin_area_profile_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor public.user_type;
begin
  select user_type into v_actor from public.profiles where id = auth.uid();
  if v_actor = 'admin_area' then
    if old.user_type = 'admin_geral' then
      raise exception 'Um administrador de filial não pode editar um administrador geral.';
    end if;
    if new.user_type = 'admin_geral' then
      raise exception 'Um administrador de filial não pode promover ninguém a administrador geral.';
    end if;
    if old.filial_id is distinct from private.my_filial_id() then
      raise exception 'Você só pode editar usuários da sua própria filial.';
    end if;
    if new.filial_id is distinct from private.my_filial_id() then
      raise exception 'Você não pode mover um usuário para outra filial.';
    end if;
  end if;
  return new;
end; $$;
create trigger trg_validate_admin_area_profile_update before update on public.profiles
  for each row execute function public.fn_validate_admin_area_profile_update();

-- ── MÁQUINA DE ESTADOS: movimentacoes (Camada 1) ───────────────
create or replace function public.fn_valida_transicao_movimentacao()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_status public.status_ferramenta;
  v_filial uuid;
begin
  select status, filial_id into v_status, v_filial from public.ferramentas where id = new.ferramenta_id for update;
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
create trigger trg_valida_movimentacao before insert on public.movimentacoes
  for each row execute function public.fn_valida_transicao_movimentacao();

create or replace function public.fn_aplicar_movimentacao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  case new.tipo
    when 'retirada' then
      update public.ferramentas set status='com_colaborador', colaborador_atual_id=new.pessoa_responsavel_id where id=new.ferramenta_id;
    when 'devolucao' then
      update public.ferramentas set status='disponivel', colaborador_atual_id=null where id=new.ferramenta_id;
    when 'envio_afericao' then
      update public.ferramentas set status='em_afericao', data_saida_afericao=new.data::date where id=new.ferramenta_id;
    when 'retorno_afericao' then
      update public.ferramentas set status='disponivel', data_retorno_afericao=new.data::date,
        data_ultima_afericao=new.data::date, data_proxima_afericao=(new.data::date + interval '1 year')::date
        where id=new.ferramenta_id;
    when 'envio_conserto' then
      update public.ferramentas set status='em_conserto' where id=new.ferramenta_id;
    when 'retorno_conserto' then
      update public.ferramentas set status='disponivel' where id=new.ferramenta_id;
    when 'extravio' then
      update public.ferramentas set status='extraviada', colaborador_atual_id=null where id=new.ferramenta_id;
    when 'baixa' then
      update public.ferramentas set status='baixada', ativo=false, colaborador_atual_id=null where id=new.ferramenta_id;
    when 'reativacao' then
      update public.ferramentas set status='disponivel', ativo=true where id=new.ferramenta_id;
  end case;
  return new;
end; $$;
create trigger trg_aplicar_movimentacao after insert on public.movimentacoes
  for each row execute function public.fn_aplicar_movimentacao();

-- ── MANUTENÇÕES (envio/retorno de conserto) ─────────────────────
create or replace function public.fn_valida_envio_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_status public.status_ferramenta; v_filial uuid;
begin
  select status, filial_id into v_status, v_filial from public.ferramentas where id = new.ferramenta_id for update;
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
create trigger trg_valida_envio_conserto before insert on public.manutencoes
  for each row execute function public.fn_valida_envio_conserto();

create or replace function public.fn_aplicar_envio_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.ferramentas set status='em_conserto' where id = new.ferramenta_id;
  perform set_config('app.internal_write','true', true);
  insert into public.movimentacoes(ferramenta_id, tipo, registrado_por, observacao)
    values (new.ferramenta_id, 'envio_conserto', new.registrado_por, new.motivo);
  perform set_config('app.internal_write','false', true);
  return new;
end; $$;
create trigger trg_aplicar_envio_conserto after insert on public.manutencoes
  for each row execute function public.fn_aplicar_envio_conserto();

create or replace function public.fn_valida_retorno_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_filial uuid;
begin
  if old.status <> 'em_conserto' then
    raise exception 'Esse registro de conserto já foi encerrado.';
  end if;
  select filial_id into v_filial from public.ferramentas where id = old.ferramenta_id;
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
create trigger trg_valida_retorno_conserto before update on public.manutencoes
  for each row when (old.status = 'em_conserto' and new.status is distinct from old.status)
  execute function public.fn_valida_retorno_conserto();

create or replace function public.fn_aplicar_retorno_conserto()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('app.internal_write','true', true);
  if new.status = 'concluido' then
    update public.ferramentas set status='disponivel' where id = new.ferramenta_id;
    insert into public.movimentacoes(ferramenta_id, tipo, registrado_por, observacao)
      values (new.ferramenta_id, 'retorno_conserto', auth.uid(), new.observacoes);
  else
    update public.ferramentas set status='baixada', ativo=false, colaborador_atual_id=null where id = new.ferramenta_id;
    insert into public.movimentacoes(ferramenta_id, tipo, registrado_por, observacao)
      values (new.ferramenta_id, 'baixa', auth.uid(), coalesce(new.observacoes,'Baixada após conserto sem sucesso.'));
  end if;
  perform set_config('app.internal_write','false', true);
  return new;
end; $$;
create trigger trg_aplicar_retorno_conserto after update on public.manutencoes
  for each row when (old.status = 'em_conserto' and new.status is distinct from old.status)
  execute function public.fn_aplicar_retorno_conserto();

-- ── RLS: habilitar ──────────────────────────────────────────────
alter table public.filiais enable row level security;
alter table public.profiles enable row level security;
alter table public.ferramentas enable row level security;
alter table public.movimentacoes enable row level security;
alter table public.manutencoes enable row level security;
alter table public.auditorias_ferramentaria enable row level security;
alter table public.auditoria_itens enable row level security;
alter table public.notifications enable row level security;
alter table public.password_reset_tokens enable row level security;

-- filiais
create policy filiais_select on public.filiais for select to authenticated using (true);
create policy filiais_admin_write on public.filiais for all to authenticated
  using (private.is_admin_geral()) with check (private.is_admin_geral());

-- profiles (insert/delete só via service_role nas Edge Functions)
create policy profiles_select on public.profiles for select to authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or private.is_admin_geral() or private.is_admin_area_ou_geral())
  with check (id = auth.uid() or private.is_admin_geral() or private.is_admin_area_ou_geral());

-- ferramentas
create policy ferramentas_select on public.ferramentas for select to authenticated
  using (private.is_admin_geral() or filial_id = private.my_filial_id());
create policy ferramentas_insert on public.ferramentas for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));
create policy ferramentas_update on public.ferramentas for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));
revoke update on public.ferramentas from authenticated;
grant update (nome, codigo, categoria, observacoes) on public.ferramentas to authenticated;

-- movimentacoes (append-only)
create policy movimentacoes_select on public.movimentacoes for select to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.ferramentas f where f.id = movimentacoes.ferramenta_id and f.filial_id = private.my_filial_id()));
create policy movimentacoes_insert on public.movimentacoes for insert to authenticated
  with check (private.is_ativo());
revoke update, delete on public.movimentacoes from authenticated;

-- manutencoes
create policy manutencoes_select on public.manutencoes for select to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.ferramentas f where f.id = manutencoes.ferramenta_id and f.filial_id = private.my_filial_id()));
create policy manutencoes_insert on public.manutencoes for insert to authenticated
  with check (private.is_ativo());
create policy manutencoes_update on public.manutencoes for update to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.ferramentas f where f.id = manutencoes.ferramenta_id and f.filial_id = private.my_filial_id()))
  with check (private.is_admin_geral() or exists (select 1 from public.ferramentas f where f.id = manutencoes.ferramenta_id and f.filial_id = private.my_filial_id()));
revoke update on public.manutencoes from authenticated;
grant update (status, observacoes, data_retorno_real) on public.manutencoes to authenticated;
revoke delete on public.manutencoes from authenticated;

-- auditorias_ferramentaria
create policy auditorias_select on public.auditorias_ferramentaria for select to authenticated
  using (private.is_admin_geral() or filial_id = private.my_filial_id());
create policy auditorias_insert on public.auditorias_ferramentaria for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));
create policy auditorias_update on public.auditorias_ferramentaria for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and filial_id = private.my_filial_id()));
create policy auditorias_delete on public.auditorias_ferramentaria for delete to authenticated
  using (private.is_admin_geral());

-- auditoria_itens
create policy auditoria_itens_select on public.auditoria_itens for select to authenticated
  using (private.is_admin_geral() or exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and a.filial_id = private.my_filial_id()));
create policy auditoria_itens_insert on public.auditoria_itens for insert to authenticated
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and a.filial_id = private.my_filial_id())));
create policy auditoria_itens_update on public.auditoria_itens for update to authenticated
  using (private.is_admin_geral() or (private.is_admin_area_ou_geral() and exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and a.filial_id = private.my_filial_id())))
  with check (private.is_admin_geral() or (private.is_admin_area_ou_geral() and exists (select 1 from public.auditorias_ferramentaria a where a.id = auditoria_itens.auditoria_id and a.filial_id = private.my_filial_id())));

-- notifications (só o próprio usuário; insert só via trigger/service role)
create policy notifications_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke insert, delete on public.notifications from authenticated;

-- password_reset_tokens: sem acesso de cliente algum (só service_role, que ignora RLS)
revoke all on public.password_reset_tokens from authenticated, anon;

-- ── SEED: filiais ────────────────────────────────────────────────
insert into public.filiais (nome) values
  ('Betim'), ('Juiz de Fora'), ('Montes Claros'),
  ('Pouso Alegre'), ('Divinópolis'), ('Belo Horizonte');

-- ── AUTOMAÇÃO DE ALERTAS (pg_cron, 1x/dia) ──────────────────────
create extension if not exists pg_cron with schema extensions;

create or replace function public.fn_gerar_notificacoes_operacionais()
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'afericao_proxima',
    'Aferição próxima do prazo',
    'A ferramenta ' || f.codigo || ' - ' || f.nome || ' tem aferição prevista para ' || to_char(f.data_proxima_afericao,'DD/MM/YYYY') || '.',
    f.id
  from public.ferramentas f
  join public.profiles p on p.filial_id = f.filial_id and p.user_type in ('admin_geral','admin_area') and p.is_active
  where f.ativo and f.status <> 'em_afericao'
    and f.data_proxima_afericao is not null
    and f.data_proxima_afericao <= current_date + interval '7 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = f.id and n.type = 'afericao_proxima' and n.created_at::date = current_date
    );

  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'retirada_atrasada',
    'Ferramenta emprestada há muito tempo',
    'A ferramenta ' || f.codigo || ' - ' || f.nome || ' está com um colaborador há mais de 30 dias.',
    f.id
  from public.ferramentas f
  join public.profiles p on p.filial_id = f.filial_id and p.user_type in ('admin_geral','admin_area') and p.is_active
  where f.status = 'com_colaborador'
    and exists (
      select 1 from public.movimentacoes m
      where m.ferramenta_id = f.id and m.tipo = 'retirada' and m.data <= now() - interval '30 days'
      order by m.data desc limit 1
    )
    and not exists (
      select 1 from public.notifications n
      where n.related_id = f.id and n.type = 'retirada_atrasada' and n.created_at::date = current_date
    );
end; $$;

select cron.schedule('notificacoes-ferramentaria-diarias','0 10 * * *',
  $$select public.fn_gerar_notificacoes_operacionais();$$);
