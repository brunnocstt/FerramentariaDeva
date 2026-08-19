-- Controle de licença/assinatura pra equipamentos de diagnóstico eletrônico (E.A.S.Y.,
-- UDT) — análogo ao controle de aferição que já existe pra instrumentos de medição, mas
-- como só tipos específicos dentro de "Equipamentos de diagnóstico" precisam disso (o
-- Cabo OBD, por exemplo, não tem licença própria), a flag fica no CATÁLOGO (por tipo de
-- ferramenta), não na categoria inteira como requer_afericao.
--
-- Os campos existem tanto em ferramentas_unidade quanto em estoque_pool porque um tipo
-- com licença pode estar cadastrado como unidade individual OU como estoque por
-- quantidade (hoje é o caso do "Rastreador UDT", cadastrado como estoque qtd=1).

alter table public.ferramentas_catalogo add column requer_licenca boolean not null default false;
comment on column public.ferramentas_catalogo.requer_licenca is
  'Esse tipo de ferramenta depende de uma licença/assinatura de software válida (ex.: scanners de diagnóstico).';

alter table public.ferramentas_unidade add column numero_licenca text;
alter table public.ferramentas_unidade add column data_validade_licenca date;
-- ferramentas_unidade tem REVOKE de coluna desde a Rodada 1 (só codigo/localizacao/observacoes
-- eram editáveis direto) — precisa de GRANT explícito pras colunas novas, senão ninguém consegue
-- editar (mesma pegadinha já documentada quando "localizacao" foi adicionada).
grant update (numero_licenca, data_validade_licenca) on public.ferramentas_unidade to authenticated;

alter table public.estoque_pool add column numero_licenca text;
alter table public.estoque_pool add column data_validade_licenca date;
-- estoque_pool nunca teve REVOKE de coluna (grant de tabela inteira já cobre colunas novas).

-- Marca os 2 sistemas que o usuário identificou como precisando de controle de licença.
update public.ferramentas_catalogo set requer_licenca = true
  where nome in ('E.A.S.Y. Light', 'Rastreador UDT');

-- ══ BUG REAL ACHADO DE PASSAGEM: fn_gerar_notificacoes_operacionais ainda referenciava a
-- tabela public.ferramentas, dropada na Rodada 2 (13/08) quando o modelo virou
-- catálogo/unidade/pool — o cron "notificacoes-ferramentaria-diarias" vinha FALHANDO TODO
-- DIA desde então (confirmado em cron.job_run_details: "relation public.ferramentas does
-- not exist", 5 execuções seguidas). Reescrita pra usar ferramentas_unidade + catálogo, e
-- aproveitado pra adicionar o aviso de licença vencendo/vencida (unidade e pool).
create or replace function public.fn_gerar_notificacoes_operacionais()
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- aferições vencendo nos próximos 7 dias (só unidades individuais têm aferição)
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'afericao_proxima',
    'Aferição próxima do prazo',
    'A ferramenta ' || fu.codigo || ' - ' || fc.nome || ' tem aferição prevista para ' || to_char(fu.data_proxima_afericao,'DD/MM/YYYY') || '.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.filial_id = fu.filial_id and p.user_type in ('admin_geral','admin_area') and p.is_active
  where fu.ativo and fu.status <> 'em_afericao'
    and fu.data_proxima_afericao is not null
    and fu.data_proxima_afericao <= current_date + interval '7 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = fu.id and n.type = 'afericao_proxima' and n.created_at::date = current_date
    );

  -- ferramentas emprestadas há mais de 30 dias sem devolução
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'retirada_atrasada',
    'Ferramenta emprestada há muito tempo',
    'A ferramenta ' || fu.codigo || ' - ' || fc.nome || ' está com um colaborador há mais de 30 dias.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.filial_id = fu.filial_id and p.user_type in ('admin_geral','admin_area') and p.is_active
  where fu.status = 'com_colaborador'
    and fu.data_retirada_atual is not null
    and fu.data_retirada_atual <= now() - interval '30 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = fu.id and n.type = 'retirada_atrasada' and n.created_at::date = current_date
    );

  -- licenças vencendo nos próximos 7 dias ou já vencidas — unidades individuais
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'licenca_proxima',
    case when fu.data_validade_licenca < current_date then 'Licença vencida' else 'Licença próxima do vencimento' end,
    'A licença de ' || fu.codigo || ' - ' || fc.nome || ' vence em ' || to_char(fu.data_validade_licenca,'DD/MM/YYYY') || '.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.filial_id = fu.filial_id and p.user_type in ('admin_geral','admin_area') and p.is_active
  where fu.ativo and fc.requer_licenca and fu.data_validade_licenca is not null
    and fu.data_validade_licenca <= current_date + interval '7 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = fu.id and n.type = 'licenca_proxima' and n.created_at::date = current_date
    );

  -- licenças vencendo nos próximos 7 dias ou já vencidas — estoque por quantidade
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'licenca_proxima',
    case when ep.data_validade_licenca < current_date then 'Licença vencida' else 'Licença próxima do vencimento' end,
    'A licença de ' || fc.nome || ' vence em ' || to_char(ep.data_validade_licenca,'DD/MM/YYYY') || '.',
    ep.id
  from public.estoque_pool ep
  join public.ferramentas_catalogo fc on fc.id = ep.catalogo_id
  join public.profiles p on p.filial_id = ep.filial_id and p.user_type in ('admin_geral','admin_area') and p.is_active
  where fc.requer_licenca and ep.data_validade_licenca is not null
    and ep.data_validade_licenca <= current_date + interval '7 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = ep.id and n.type = 'licenca_proxima' and n.created_at::date = current_date
    );
end; $$;
