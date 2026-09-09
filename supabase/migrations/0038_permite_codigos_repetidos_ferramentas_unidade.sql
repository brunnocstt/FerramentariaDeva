-- Ferramentas do checklist Especifer/Iveco usam o código do fabricante como "código" — o mesmo
-- valor pra todas as unidades físicas idênticas daquele item (não é um número de série único).
-- Uma filial pode legitimamente ter 2+ unidades com o mesmo código. A constraint antiga
-- (filial_id, codigo) única impedia cadastrar a 2ª unidade — bloqueando exatamente esse caso.
alter table public.ferramentas_unidade drop constraint ferramentas_unidade_filial_id_codigo_key;
