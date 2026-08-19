-- BUG REAL achado testando a feature de licença (0013): o join `p.filial_id = fu.filial_id`
-- nunca inclui admin_geral (que sempre tem filial_id null por design) — como hoje não existe
-- nenhum admin_area cadastrado, NENHUMA notificação operacional (aferição, atraso, licença)
-- estava chegando a ninguém, mesmo depois do fix da tabela dropada em 0013. Corrigido pra
-- admin_geral sempre receber (supervisiona tudo), admin_area continua só da própria filial.
-- Confirmado via teste em sessão simulada: rodando a função depois desse fix, as duas
-- notificações de teste (licença vencendo + vencida) chegaram certinho pro admin_geral.
create or replace function public.fn_gerar_notificacoes_operacionais()
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'afericao_proxima',
    'Aferição próxima do prazo',
    'A ferramenta ' || fu.codigo || ' - ' || fc.nome || ' tem aferição prevista para ' || to_char(fu.data_proxima_afericao,'DD/MM/YYYY') || '.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.is_active and (p.user_type = 'admin_geral' or (p.user_type = 'admin_area' and p.filial_id = fu.filial_id))
  where fu.ativo and fu.status <> 'em_afericao'
    and fu.data_proxima_afericao is not null
    and fu.data_proxima_afericao <= current_date + interval '7 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = fu.id and n.type = 'afericao_proxima' and n.created_at::date = current_date
    );

  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'retirada_atrasada',
    'Ferramenta emprestada há muito tempo',
    'A ferramenta ' || fu.codigo || ' - ' || fc.nome || ' está com um colaborador há mais de 30 dias.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.is_active and (p.user_type = 'admin_geral' or (p.user_type = 'admin_area' and p.filial_id = fu.filial_id))
  where fu.status = 'com_colaborador'
    and fu.data_retirada_atual is not null
    and fu.data_retirada_atual <= now() - interval '30 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = fu.id and n.type = 'retirada_atrasada' and n.created_at::date = current_date
    );

  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'licenca_proxima',
    case when fu.data_validade_licenca < current_date then 'Licença vencida' else 'Licença próxima do vencimento' end,
    'A licença de ' || fu.codigo || ' - ' || fc.nome || ' vence em ' || to_char(fu.data_validade_licenca,'DD/MM/YYYY') || '.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.is_active and (p.user_type = 'admin_geral' or (p.user_type = 'admin_area' and p.filial_id = fu.filial_id))
  where fu.ativo and fc.requer_licenca and fu.data_validade_licenca is not null
    and fu.data_validade_licenca <= current_date + interval '7 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = fu.id and n.type = 'licenca_proxima' and n.created_at::date = current_date
    );

  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'licenca_proxima',
    case when ep.data_validade_licenca < current_date then 'Licença vencida' else 'Licença próxima do vencimento' end,
    'A licença de ' || fc.nome || ' vence em ' || to_char(ep.data_validade_licenca,'DD/MM/YYYY') || '.',
    ep.id
  from public.estoque_pool ep
  join public.ferramentas_catalogo fc on fc.id = ep.catalogo_id
  join public.profiles p on p.is_active and (p.user_type = 'admin_geral' or (p.user_type = 'admin_area' and p.filial_id = ep.filial_id))
  where fc.requer_licenca and ep.data_validade_licenca is not null
    and ep.data_validade_licenca <= current_date + interval '7 days'
    and not exists (
      select 1 from public.notifications n
      where n.related_id = ep.id and n.type = 'licenca_proxima' and n.created_at::date = current_date
    );
end; $$;
