-- Os relatórios mais novos (Betim 18/09/2026, Juiz de Fora 09/10/2026) trazem 4 itens que a lista
-- mestre tinha tirado quando só existia o relatório de Montes Claros (migrations 0032 e 0034 —
-- removidos por "o auditor não encontrou", o que confundia o item com a presença dele no programa).
-- O programa da Especifer é um só pra todas as filiais, então o item pertence à lista independente
-- de alguma filial ter ou não achado a ferramenta.
insert into public.checklist_especifer_itens(ordem, codigo, codigo_alternativo, descricao)
select (select max(ordem) from public.checklist_especifer_itens) + v.n, v.codigo, v.alt, v.descricao
from (values
  (1,'99340054','380000121','FERRAMENTA PARA REMOCAO DO RETENTOR TRASEIRO DO MOTOR'),
  (2,'500056946',null,'SOQUETE PARA MONTAGEM TUBO D''AGUA MOTOR C13'),
  (3,'99371062',null,'Suporte para a caixa do câmbio durante as intervenções de revisão'),
  (4,'500093484',null,'Ferramenta compressão montagem do atuador LCA')
) as v(n,codigo,alt,descricao)
where not exists (select 1 from public.checklist_especifer_itens m where m.codigo=v.codigo);

-- 99340054 já tem catálogo cadastrado (Remoção Retentor Traseiro, em MOC e Betim): volta a vincular
-- e a marcar como obrigatória.
update public.checklist_especifer_itens set catalogo_id='1d8f8d9f-b9dc-44c1-91a6-83b488998477' where codigo='99340054';
update public.ferramentas_catalogo set obrigatoria=true where id='1d8f8d9f-b9dc-44c1-91a6-83b488998477';
