-- Bucket privado pra guardar o PDF de cada relatório oficial Especifer/Iveco. Só o caminho do
-- arquivo fica na tabela (texto) — o arquivo em si vive no Storage, fora do banco relacional.
insert into storage.buckets (id, name, public)
values ('checklist-especifer-pdfs', 'checklist-especifer-pdfs', false)
on conflict (id) do nothing;

-- Leitura: qualquer usuário autenticado (mesmo padrão das outras tabelas do checklist).
create policy "authenticated pode ler pdfs checklist especifer"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'checklist-especifer-pdfs');

-- Escrita: só admin_geral/admin_area podem enviar, atualizar ou remover o PDF de um relatório.
create policy "admin pode enviar pdfs checklist especifer"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'checklist-especifer-pdfs'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.user_type in ('admin_geral','admin_area'))
  );

create policy "admin pode atualizar pdfs checklist especifer"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'checklist-especifer-pdfs'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.user_type in ('admin_geral','admin_area'))
  )
  with check (
    bucket_id = 'checklist-especifer-pdfs'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.user_type in ('admin_geral','admin_area'))
  );

create policy "admin pode remover pdfs checklist especifer"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'checklist-especifer-pdfs'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.user_type in ('admin_geral','admin_area'))
  );

alter table public.checklist_especifer_auditorias add column pdf_path text;
comment on column public.checklist_especifer_auditorias.pdf_path is
  'Caminho do arquivo no bucket checklist-especifer-pdfs (Storage) — o PDF original do relatório, se enviado.';
