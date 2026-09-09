-- Registro histórico do resultado de cada relatório oficial Especifer/Iveco por filial — é um
-- fato fixo daquele dia específico de auditoria (ex.: "247 de 251 confirmadas, nota 98"), bem
-- diferente do widget "Atingimento" do Dashboard (que recalcula ao vivo quantas ferramentas
-- obrigatórias têm estoque disponível agora). Os dois números divergem naturalmente com o tempo
-- — este aqui não deve ser recalculado, só consultado.
create table public.checklist_especifer_auditorias (
  id uuid primary key default gen_random_uuid(),
  filial_id uuid not null references public.filiais(id),
  relatorio_numero text,
  data_conclusao date not null,
  total_avaliativos integer not null,
  inconformidades integer not null,
  nota integer,
  created_at timestamptz not null default now()
);
comment on table public.checklist_especifer_auditorias is
  'Resultado fechado de cada relatório oficial Especifer/Iveco (Programa de Verificação de Ferramentas) por filial — fato histórico, não recalculado.';

alter table public.checklist_especifer_auditorias enable row level security;
create policy "authenticated pode ler auditorias especifer"
  on public.checklist_especifer_auditorias for select
  to authenticated using (true);

insert into public.checklist_especifer_auditorias
  (filial_id, relatorio_numero, data_conclusao, total_avaliativos, inconformidades, nota)
values
  ('8318dbab-b524-4324-bba3-39ede8573a74', '215739150', '2026-09-09', 251, 4, 98);
