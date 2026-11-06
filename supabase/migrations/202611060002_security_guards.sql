-- Keep customer-editable fields narrow even when a user submits direct REST updates.
create or replace function public.guard_profile_updates() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is not null and not public.is_admin() and new.role is distinct from old.role then
    raise exception 'Only an administrator can change account roles';
  end if;
  return new;
end $$;
drop trigger if exists guard_profile_role on public.profiles;
create trigger guard_profile_role before update on public.profiles for each row execute procedure public.guard_profile_updates();

create or replace function public.guard_customer_quotation_response() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if old.customer_id is distinct from auth.uid()
      or old.status <> 'sent'
      or new.status not in ('accepted','rejected')
      or new.customer_id is distinct from old.customer_id
      or new.inquiry_id is distinct from old.inquiry_id
      or new.quote_number is distinct from old.quote_number
      or new.currency is distinct from old.currency
      or new.subtotal is distinct from old.subtotal
      or new.tax_amount is distinct from old.tax_amount
      or new.total_amount is distinct from old.total_amount
      or new.valid_until is distinct from old.valid_until
      or new.notes is distinct from old.notes
      or new.document_path is distinct from old.document_path
      or new.sent_at is distinct from old.sent_at then
      raise exception 'Customers can only accept or reject sent quotations';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_customer_quotation_response on public.quotations;
create trigger guard_customer_quotation_response before update on public.quotations for each row execute procedure public.guard_customer_quotation_response();

create or replace function public.attach_quotation_customer() returns trigger language plpgsql security definer set search_path=public as $$
begin
  select user_id into new.customer_id from public.inquiries where id=new.inquiry_id;
  if new.status='sent' and new.sent_at is null then new.sent_at=now(); end if;
  return new;
end $$;
drop trigger if exists attach_quotation_customer on public.quotations;
create trigger attach_quotation_customer before insert or update of inquiry_id,status on public.quotations for each row execute procedure public.attach_quotation_customer();

create or replace function public.guard_customer_inquiry_updates() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Only administrators can update inquiry records';
  end if;
  return new;
end $$;
drop trigger if exists guard_customer_inquiry_updates on public.inquiries;
create trigger guard_customer_inquiry_updates before update on public.inquiries for each row execute procedure public.guard_customer_inquiry_updates();

grant execute on function public.is_admin() to anon;
