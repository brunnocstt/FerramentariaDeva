-- Marca ferramentas do catálogo que sabemos que existem/são obrigatórias (confirmadas pelo
-- relatório oficial Especifer/Iveco, inclusive com fotos), mas cuja alocação física real
-- (unidade/filial/local) ainda não foi mapeada na ferramentaria. Evita confundir "ainda não
-- sabemos onde está" com "auditoria constatou que falta".
alter table public.ferramentas_catalogo
  add column pendente_alocacao boolean not null default false;

comment on column public.ferramentas_catalogo.pendente_alocacao is
  'Ferramenta confirmada como existente/obrigatória pelo checklist oficial, mas sem unidade (ferramentas_unidade) ou estoque (estoque_pool) cadastrado ainda — alocação física pendente de mapeamento.';

-- Nota: os 25 registros novos de catálogo + checklist_especifer_itens (checklist atualizado
-- Especifer Montes Claros, 09/2026 — áreas 1, 10, 11, 12, 13 e 14: kit UDT, caixa de câmbio
-- ZF-Traxon, cubo de roda Dana S16-130, kit S-WAY Euro 6, caixa de câmbio Eaton EAO-6606 e
-- MHD-EVO Eaton) foram inseridos via execute_sql na mesma sessão, não fazem parte deste
-- arquivo de migration (é dado, não DDL). Ver histórico/relatório do checklist para a lista
-- completa dos 25 códigos e descrições.
