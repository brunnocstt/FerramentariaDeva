-- Problema 1: "cadastrei a locação de uma peça pendente, mas o registro ficou duplicado
-- (uma disponível, outra ainda pendente)". Causa: a política de escrita em
-- ferramentas_catalogo só permitia admin_geral (catalogo_write ALL... is_admin_geral()).
-- Quando um admin_area (gestor de filial) cadastrava a primeira unidade de um item pendente,
-- o UPDATE que zera pendente_alocacao era bloqueado pelo RLS silenciosamente (0 linhas
-- afetadas, sem erro) — a unidade era criada normalmente, mas o catálogo continuava marcado
-- como pendente, dando a impressão de duplicidade na tela.
--
-- Correção: em vez de o cliente tentar dar UPDATE em ferramentas_catalogo (sujeito a RLS e ao
-- papel de quem está logado), um trigger cuida disso automaticamente — mesmo padrão já usado
-- no resto do app (trocar UPDATE direto do cliente por trigger SECURITY DEFINER em colunas
-- operacionais). Dispara ao criar a primeira unidade/estoque pra aquele catálogo, não importa
-- quem cadastrou.
create or replace function private.fn_limpar_pendente_alocacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.ferramentas_catalogo
  set pendente_alocacao = false
  where id = new.catalogo_id and pendente_alocacao = true;
  return new;
end;
$$;

create trigger trg_limpar_pendente_alocacao_unidade
after insert on public.ferramentas_unidade
for each row execute function private.fn_limpar_pendente_alocacao();

create trigger trg_limpar_pendente_alocacao_pool
after insert on public.estoque_pool
for each row execute function private.fn_limpar_pendente_alocacao();

-- Problema 2: "preciso cadastrar ferramenta nova, mas ela não está na lista, como insiro?".
-- Causa: a mesma política catalogo_write (ALL, só admin_geral) também bloqueava um admin_area
-- de cadastrar um tipo de ferramenta novo no catálogo (compartilhado entre filiais) quando ele
-- não existia ainda. Divide a política única em INSERT (admin_geral OU admin_area — a
-- constraint de nome único já evita duplicidade real entre filiais) e UPDATE/DELETE (continuam
-- só admin_geral — renomear/alterar obrigatoriedade de um item que já existe pra todo mundo
-- continua reservado ao admin geral).
drop policy "catalogo_write" on public.ferramentas_catalogo;

create policy "catalogo_insert" on public.ferramentas_catalogo
  for insert to authenticated
  with check (private.is_admin_area_ou_geral());

create policy "catalogo_update" on public.ferramentas_catalogo
  for update to authenticated
  using (private.is_admin_geral())
  with check (private.is_admin_geral());

create policy "catalogo_delete" on public.ferramentas_catalogo
  for delete to authenticated
  using (private.is_admin_geral());

-- Backfill: qualquer catálogo marcado pendente_alocacao que já tem unidade/estoque cadastrado
-- (vítima do bug 1 antes da correção) — o Extrator do print do Gilmar é um desses casos.
update public.ferramentas_catalogo fc
set pendente_alocacao = false
where fc.pendente_alocacao = true
  and (
    exists (select 1 from public.ferramentas_unidade fu where fu.catalogo_id = fc.id)
    or exists (select 1 from public.estoque_pool ep where ep.catalogo_id = fc.id)
  );
