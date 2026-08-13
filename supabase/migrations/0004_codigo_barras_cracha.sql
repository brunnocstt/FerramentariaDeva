-- ════════════════════════════════════════════════════════════════
-- Código de barras do crachá: filial + matrícula no mesmo código.
--
-- Formato observado no crachá (12 dígitos), ex. Robert (Betim, matrícula 830):
--   055003000830
--   └──┬───┘└──┬───┘
--    metade 1   metade 2
--  "055003"→55003   "000830"→830
--
-- O código é dividido ao meio: a primeira metade identifica a filial
-- (cadastrada abaixo em filiais.codigo_barras) e a segunda metade,
-- convertida para inteiro (descarta zeros à esquerda), é a matrícula.
-- Isso cobre o pedido do usuário de aceitar matrícula com 3 ou 4
-- dígitos (até 999999 na prática, já que a divisão é sempre "metade a
-- metade" do tamanho total do código lido).
-- ════════════════════════════════════════════════════════════════

alter table public.filiais add column codigo_barras text unique;

-- A matrícula deixa de ser única globalmente: o mesmo número de 3-4
-- dígitos pode se repetir em filiais diferentes (quem desambigua é a
-- combinação filial + matrícula, extraída do código de barras).
alter table public.profiles drop constraint profiles_matricula_key;
alter table public.profiles add constraint profiles_filial_matricula_key unique (filial_id, matricula);
