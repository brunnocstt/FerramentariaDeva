-- ════════════════════════════════════════════════════════════════
-- Correção: fn_aplicar_movimentacao (AFTER INSERT em movimentacoes)
-- não tinha um branch para o novo tipo 'transferencia' — o CASE sem
-- ELSE estourava "case not found" ao aprovar uma transferência
-- (pego em teste E2E antes de publicar). A transferência em si
-- (filial_id/status da ferramenta_unidade) já é aplicada por
-- fn_aplicar_transferencia_decisao antes desta movimentação-espelho
-- ser inserida, então aqui é só um no-op mesmo.
-- ════════════════════════════════════════════════════════════════

create or replace function public.fn_aplicar_movimentacao()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  case new.tipo
    when 'retirada' then
      update public.ferramentas_unidade set status='com_colaborador', colaborador_atual_id=new.pessoa_responsavel_id,
        data_retirada_atual=new.data where id=new.ferramenta_id;
    when 'devolucao' then
      update public.ferramentas_unidade set status='disponivel', colaborador_atual_id=null, data_retirada_atual=null where id=new.ferramenta_id;
    when 'envio_afericao' then
      update public.ferramentas_unidade set status='em_afericao', data_saida_afericao=new.data::date where id=new.ferramenta_id;
    when 'retorno_afericao' then
      update public.ferramentas_unidade set status='disponivel', data_retorno_afericao=new.data::date,
        data_ultima_afericao=new.data::date, data_proxima_afericao=(new.data::date + interval '1 year')::date
        where id=new.ferramenta_id;
    when 'envio_conserto' then
      update public.ferramentas_unidade set status='em_conserto' where id=new.ferramenta_id;
    when 'retorno_conserto' then
      update public.ferramentas_unidade set status='disponivel' where id=new.ferramenta_id;
    when 'transferencia' then
      null; -- já aplicado por fn_aplicar_transferencia_decisao antes desta movimentação ser inserida
    when 'extravio' then
      update public.ferramentas_unidade set status='extraviada', colaborador_atual_id=null, data_retirada_atual=null where id=new.ferramenta_id;
    when 'baixa' then
      update public.ferramentas_unidade set status='baixada', ativo=false, colaborador_atual_id=null, data_retirada_atual=null where id=new.ferramenta_id;
    when 'reativacao' then
      update public.ferramentas_unidade set status='disponivel', ativo=true where id=new.ferramenta_id;
  end case;
  return new;
end; $function$;
