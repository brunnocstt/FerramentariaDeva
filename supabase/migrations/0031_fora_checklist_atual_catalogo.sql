-- Sinaliza ferramentas do catálogo que estavam no checklist Especifer anterior mas não constam
-- mais no checklist mais recente (fonte de verdade atual, a partir do relatório finalizado em
-- 09/2026). Não implica baixa automática — só marca pra o gestor da filial confirmar o que
-- aconteceu (a ferramenta pode ter sido removida do programa oficial, extraviada, etc.).
alter table public.ferramentas_catalogo
  add column fora_checklist_atual boolean not null default false;

comment on column public.ferramentas_catalogo.fora_checklist_atual is
  'Ferramenta que constava no checklist Especifer/Iveco anterior mas não aparece no checklist mais recente (fonte de verdade atual) — pendente de confirmação com o gestor da filial.';

-- Aplicado manualmente via execute_sql na mesma sessão: marcado fora_checklist_atual = true
-- pro catálogo "Kit Easyscope" (id f628e732-6e6c-487a-8189-159b5213ddd7, código checklist
-- antigo 99327107) — única ferramenta do checklist anterior (228 itens) que não aparece em
-- nenhum lugar do checklist novo de Montes Claros (255 itens, relatório finalizado 09/2026).
-- Existe uma ferramentas_unidade ativa (código 99327107, status "disponivel") em Montes Claros
-- pra esse catálogo — pendente de confirmação com o gestor da filial.
