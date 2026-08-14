-- ════════════════════════════════════════════════════════════════
-- Novos valores de enum para suportar transferência de ferramenta
-- entre filiais (Rodada 3). Em arquivo próprio porque o Postgres não
-- permite usar um valor de enum recém-adicionado na mesma transação
-- em que ele foi criado.
-- ════════════════════════════════════════════════════════════════

alter type public.status_ferramenta add value if not exists 'em_transferencia';
alter type public.tipo_movimentacao add value if not exists 'transferencia';
