-- ============================================================================
-- Centmond — Phase 3a: Storage bucket "receipts" + RLS
-- Path convention: receipts/<owner_id>/<transaction_id>/<filename>
-- A user can only read/write objects under their own owner_id prefix.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts', 'receipts', false,
  10485760,  -- 10 MB
  array['image/jpeg','image/png','image/heic','image/webp','application/pdf']
)
on conflict (id) do nothing;

-- RLS on storage.objects is already enabled by Supabase; just add the policies.

create policy "receipts owner read"
  on storage.objects for select
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "receipts owner insert"
  on storage.objects for insert
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "receipts owner update"
  on storage.objects for update
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "receipts owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
