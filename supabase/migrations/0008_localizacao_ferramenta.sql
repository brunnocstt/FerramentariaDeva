-- ════════════════════════════════════════════════════════════════
-- Localização física da ferramenta dentro da filial (ex.: "Armário 3,
-- Gaveta 2", "Prateleira B"). Pedido do gestor de Montes Claros pra
-- registrar onde cada ferramenta/estoque fica guardado fisicamente
-- na oficina. Texto livre, opcional, sem impacto em RLS/triggers —
-- só cadastro, não afeta a máquina de estados.
-- ════════════════════════════════════════════════════════════════

alter table public.ferramentas_unidade add column localizacao text;
alter table public.estoque_pool add column localizacao text;

-- ferramentas_unidade só concede UPDATE explícito em (codigo, observacoes)
-- pro papel authenticated (colunas operacionais só mudam via trigger) —
-- localizacao é cadastral, então entra nessa mesma lista.
grant update (localizacao) on public.ferramentas_unidade to authenticated;
grant update (localizacao) on public.estoque_pool to authenticated;

