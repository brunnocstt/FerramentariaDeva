-- Correção: dos 25 itens novos do checklist Especifer Montes Claros (09/2026) inseridos na
-- migration 0030, 2 não foram encontrados pelo auditor na vistoria física (0/1 no relatório):
-- 99371062 (Suporte Caixa de Câmbio p/ Revisão) e 500093484 (Compressão Atuador LCA - Eaton
-- EAO-6606). Regra combinada com o usuário: ferramenta obrigatória que não constava no
-- preciário E não foi encontrada na vistoria não deve entrar no sistema — só cadastramos como
-- "pendente_alocacao" as que o auditor efetivamente confirmou existir.
delete from public.checklist_especifer_itens where codigo in ('99371062', '500093484');
delete from public.ferramentas_catalogo where id in (
  '05cd34c2-0a02-42f8-a2f3-666a3f05feff', -- Suporte Caixa de Câmbio p/ Revisão (99371062)
  'f53d44d2-a6a3-428b-9884-1d5164f1d578'  -- Compressão Atuador LCA - Eaton EAO-6606 (500093484)
);
