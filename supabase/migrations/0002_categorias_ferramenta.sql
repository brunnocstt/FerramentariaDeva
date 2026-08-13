-- ════════════════════════════════════════════════════════════════
-- Categorias de ferramenta — estrutura a categoria (antes texto livre)
-- e controla se a categoria exige aferição.
-- ════════════════════════════════════════════════════════════════

create table public.categorias_ferramenta (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  requer_afericao boolean not null default false,
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.categorias_ferramenta enable row level security;

create policy categorias_ferramenta_select on public.categorias_ferramenta for select to authenticated using (true);
create policy categorias_ferramenta_write on public.categorias_ferramenta for all to authenticated
  using (private.is_admin_geral()) with check (private.is_admin_geral());

insert into public.categorias_ferramenta (nome, requer_afericao) values
  ('Ferramentas de medição', true),
  ('Ferramentas manuais', false),
  ('Ferramentas pneumáticas', false),
  ('Ferramentas elétricas', false),
  ('Equipamentos de elevação', true),
  ('Equipamentos de diagnóstico', true),
  ('Ferramentas especiais do fabricante', false),
  ('Equipamentos de solda', false);

alter table public.ferramentas add column categoria_id uuid references public.categorias_ferramenta(id);
alter table public.ferramentas drop column categoria;

revoke update on public.ferramentas from authenticated;
grant update (nome, codigo, categoria_id, observacoes) on public.ferramentas to authenticated;
