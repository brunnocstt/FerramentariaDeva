-- Correção final do checklist Especifer Montes Claros (09/2026): as duas ferramentas
-- pré-existentes que o auditor NÃO encontrou na vistoria (99340054 e 500056946) saem do
-- checklist, mesmo tratamento já dado antes às 2 novas que também não foram encontradas
-- (99371062 e 500093484, migration 0032). "Remoção Retentor Traseiro" (catálogo de
-- 99340054) continua existindo como ferramenta cadastrada — só deixa de ser obrigatória,
-- já que não é mais exigida pelo checklist mais recente.
delete from public.checklist_especifer_itens where codigo in ('99340054', '500056946');
update public.ferramentas_catalogo set obrigatoria=false
where id='1d8f8d9f-b9dc-44c1-91a6-83b488998477'; -- Remoção Retentor Traseiro (99340054)
