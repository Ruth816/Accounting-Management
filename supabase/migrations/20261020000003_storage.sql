-- Private bucket for request attachments. Files are uploaded under
-- "<uploader id>/<random>-<file name>"; whoever can see a request that
-- lists the file can download it.

insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

create policy "upload own attachments" on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "read attachments of visible requests" on storage.objects for select to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or exists (select 1 from public.attachments a where a.storage_path = objects.name)));

create policy "delete own attachments" on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);
