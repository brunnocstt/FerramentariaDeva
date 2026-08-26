-- 1) Corrige fn_gerar_notificacoes_operacionais: aferição e licença passam a notificar
--    exatamente em 3 datas (5 dias antes, no dia, e 1 dia depois do vencimento), em vez de
--    todo dia dentro de uma janela de 7 dias (o que também nunca parava depois de vencido).
create or replace function public.fn_gerar_notificacoes_operacionais()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'afericao_proxima',
    case
      when fu.data_proxima_afericao < current_date then 'Aferição vencida'
      when fu.data_proxima_afericao = current_date then 'Aferição vence hoje'
      else 'Aferição próxima do prazo'
    end,
    'A ferramenta ' || fu.codigo || ' - ' || fc.nome || ' tem aferição prevista para ' || to_char(fu.data_proxima_afericao,'DD/MM/YYYY') || '.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.is_active and (p.user_type = 'admin_geral' or (p.user_type = 'admin_area' and p.filial_id = fu.filial_id))
  where fu.ativo and fu.status <> 'em_afericao'
    and fu.data_proxima_afericao in (current_date + 5, current_date, current_date - 1)
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
    case
      when fu.data_validade_licenca < current_date then 'Licença vencida'
      when fu.data_validade_licenca = current_date then 'Licença vence hoje'
      else 'Licença próxima do vencimento'
    end,
    'A licença de ' || fu.codigo || ' - ' || fc.nome || ' vence em ' || to_char(fu.data_validade_licenca,'DD/MM/YYYY') || '.',
    fu.id
  from public.ferramentas_unidade fu
  join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
  join public.profiles p on p.is_active and (p.user_type = 'admin_geral' or (p.user_type = 'admin_area' and p.filial_id = fu.filial_id))
  where fu.ativo and fc.requer_licenca and fu.data_validade_licenca is not null
    and fu.data_validade_licenca in (current_date + 5, current_date, current_date - 1)
    and not exists (
      select 1 from public.notifications n
      where n.related_id = fu.id and n.type = 'licenca_proxima' and n.created_at::date = current_date
    );

  insert into public.notifications (user_id, type, title, body, related_id)
  select p.id, 'licenca_proxima',
    case
      when ep.data_validade_licenca < current_date then 'Licença vencida'
      when ep.data_validade_licenca = current_date then 'Licença vence hoje'
      else 'Licença próxima do vencimento'
    end,
    'A licença de ' || fc.nome || ' vence em ' || to_char(ep.data_validade_licenca,'DD/MM/YYYY') || '.',
    ep.id
  from public.estoque_pool ep
  join public.ferramentas_catalogo fc on fc.id = ep.catalogo_id
  join public.profiles p on p.is_active and (p.user_type = 'admin_geral' or (p.user_type = 'admin_area' and p.filial_id = ep.filial_id))
  where fc.requer_licenca and ep.data_validade_licenca is not null
    and ep.data_validade_licenca in (current_date + 5, current_date, current_date - 1)
    and not exists (
      select 1 from public.notifications n
      where n.related_id = ep.id and n.type = 'licenca_proxima' and n.created_at::date = current_date
    );
end; $function$;

-- 2) Ferramenta devolvida danificada (unidade individual) → avisa todo gerente de pós-venda ativo,
--    de qualquer filial.
create or replace function public.fn_notifica_ferramenta_danificada_individual()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.tipo = 'devolucao' and new.condicao in ('parcialmente_danificada','totalmente_danificada') then
    insert into public.notifications (user_id, type, title, body, related_id)
    select p.id, 'ferramenta_danificada',
      case when new.condicao = 'totalmente_danificada' then 'Ferramenta devolvida totalmente danificada' else 'Ferramenta devolvida parcialmente danificada' end,
      'A ferramenta ' || fu.codigo || ' - ' || fc.nome || ' (filial ' || f.nome || ') foi devolvida com condição "' ||
        (case when new.condicao = 'totalmente_danificada' then 'Totalmente Danificada' else 'Parcialmente Danificada' end) || '".',
      fu.id
    from public.ferramentas_unidade fu
    join public.ferramentas_catalogo fc on fc.id = fu.catalogo_id
    join public.filiais f on f.id = fu.filial_id
    join public.profiles p on p.is_active and p.gerente_pos_vendas
    where fu.id = new.ferramenta_id;
  end if;
  return new;
end;
$function$;

revoke all on function public.fn_notifica_ferramenta_danificada_individual() from public, anon, authenticated;

drop trigger if exists trg_notifica_ferramenta_danificada on public.movimentacoes;
create trigger trg_notifica_ferramenta_danificada
  after insert on public.movimentacoes
  for each row
  execute function public.fn_notifica_ferramenta_danificada_individual();

-- 3) Mesma coisa para devolução de item em pool (empréstimos).
create or replace function public.fn_notifica_ferramenta_danificada_pool()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.condicao_devolucao is distinct from old.condicao_devolucao
     and new.condicao_devolucao in ('parcialmente_danificada','totalmente_danificada') then
    insert into public.notifications (user_id, type, title, body, related_id)
    select p.id, 'ferramenta_danificada',
      case when new.condicao_devolucao = 'totalmente_danificada' then 'Ferramenta devolvida totalmente danificada' else 'Ferramenta devolvida parcialmente danificada' end,
      'A ferramenta ' || fc.nome || ' (filial ' || f.nome || ', empréstimo de ' || new.quantidade || ' unidade(s)) foi devolvida com condição "' ||
        (case when new.condicao_devolucao = 'totalmente_danificada' then 'Totalmente Danificada' else 'Parcialmente Danificada' end) || '".',
      new.id
    from public.estoque_pool ep
    join public.ferramentas_catalogo fc on fc.id = ep.catalogo_id
    join public.filiais f on f.id = ep.filial_id
    join public.profiles p on p.is_active and p.gerente_pos_vendas
    where ep.id = new.estoque_id;
  end if;
  return new;
end;
$function$;

revoke all on function public.fn_notifica_ferramenta_danificada_pool() from public, anon, authenticated;

drop trigger if exists trg_notifica_ferramenta_danificada_pool on public.emprestimos;
create trigger trg_notifica_ferramenta_danificada_pool
  after update on public.emprestimos
  for each row
  execute function public.fn_notifica_ferramenta_danificada_pool();
