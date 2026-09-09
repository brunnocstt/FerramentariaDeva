-- Faltava a política de UPDATE em checklist_especifer_auditorias — sem ela, o
-- supabase.update({pdf_path:...}) do envio de PDF era bloqueado pelo RLS silenciosamente
-- (0 linhas afetadas, sem erro), então o arquivo subia pro Storage mas a referência nunca
-- era salva na tabela.
create policy "admin pode atualizar auditorias especifer"
  on public.checklist_especifer_auditorias for update
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.user_type in ('admin_geral','admin_area')))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.user_type in ('admin_geral','admin_area')));

-- Backfill: o PDF de Montes Claros já estava no Storage (upload funcionou), só faltava
-- linkar o caminho na linha da auditoria.
update public.checklist_especifer_auditorias
set pdf_path = '8318dbab-b524-4324-bba3-39ede8573a74/ed330a90-9673-4b4a-8498-f7d2abb7d934.pdf'
where id = 'ed330a90-9673-4b4a-8498-f7d2abb7d934';
