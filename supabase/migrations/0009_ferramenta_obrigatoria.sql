-- Marca ferramentas obrigatórias segundo a checklist de "Ferramentas Indispensáveis" da Iveco/Especifer.
-- Campo no catálogo (global), não por filial, pois a exigência é do fabricante e não varia por unidade.
alter table public.ferramentas_catalogo
  add column obrigatoria boolean not null default false;

comment on column public.ferramentas_catalogo.obrigatoria is
  'Ferramenta indispensável conforme checklist Iveco/Especifer (Programa de Verificação de Ferramentas).';
