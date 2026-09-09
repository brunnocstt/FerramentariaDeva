-- Detalhe de quais ferramentas especificamente não foram encontradas em cada auditoria
-- Especifer registrada — pra mostrar dentro do dropdown de cada relatório na tela Checklists.
create table public.checklist_especifer_auditoria_itens (
  id uuid primary key default gen_random_uuid(),
  auditoria_id uuid not null references public.checklist_especifer_auditorias(id) on delete cascade,
  codigo text not null,
  descricao text not null,
  created_at timestamptz not null default now()
);
comment on table public.checklist_especifer_auditoria_itens is
  'Ferramentas obrigatórias que NÃO foram encontradas numa auditoria Especifer específica (checklist_especifer_auditorias) — detalhe pro dropdown do relatório na tela Checklists.';

alter table public.checklist_especifer_auditoria_itens enable row level security;
create policy "authenticated pode ler itens nao encontrados"
  on public.checklist_especifer_auditoria_itens for select
  to authenticated using (true);

insert into public.checklist_especifer_auditoria_itens (auditoria_id, codigo, descricao)
select a.id, v.codigo, v.descricao
from public.checklist_especifer_auditorias a,
  (values
    ('99340054','Ferramenta para remoção do retentor traseiro do motor'),
    ('500056946','Soquete para montagem tubo d''água motor C13'),
    ('99371062','Suporte para a caixa do câmbio durante as intervenções de revisão'),
    ('500093484','Ferramenta compressão montagem do atuador LCA')
  ) as v(codigo,descricao)
where a.relatorio_numero='215739150';
