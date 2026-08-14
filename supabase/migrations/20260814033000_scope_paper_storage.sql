create unique index if not exists papers_storage_key_unique
on public.papers (storage_key)
where storage_key is not null;

drop policy if exists "Users can upload paper files to their folder"
on storage.objects;
drop policy if exists "Users can read their paper files"
on storage.objects;
drop policy if exists "Users can update their paper files"
on storage.objects;
drop policy if exists "Users can delete their paper files"
on storage.objects;

create policy "Project owners can upload paper files"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] in (
    select projects.id::text
    from public.projects
    where projects.owner_id = auth.uid()
  )
  and lower(storage.extension(name)) = 'pdf'
);

create policy "Project owners can read paper files"
on storage.objects for select
to authenticated
using (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] in (
    select projects.id::text
    from public.projects
    where projects.owner_id = auth.uid()
  )
);

create policy "Project owners can update paper files"
on storage.objects for update
to authenticated
using (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] in (
    select projects.id::text
    from public.projects
    where projects.owner_id = auth.uid()
  )
)
with check (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] in (
    select projects.id::text
    from public.projects
    where projects.owner_id = auth.uid()
  )
  and lower(storage.extension(name)) = 'pdf'
);

create policy "Project owners can delete paper files"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'private-papers'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] in (
    select projects.id::text
    from public.projects
    where projects.owner_id = auth.uid()
  )
);
