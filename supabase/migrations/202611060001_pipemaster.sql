-- PipeMaster Engineering application schema. Apply with `supabase db push`.
create extension if not exists pgcrypto;

create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '', company_name text not null default '', phone text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin')
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','')); return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(), key text not null unique check(key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title text not null check(length(title) between 2 and 180), category text not null check(length(category) between 2 and 80),
  summary text not null default '' check(length(summary)<=500), description text not null default '' check(length(description)<=20000), image_url text, icon text,
  active boolean not null default true, sort_order integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(), slug text not null unique check(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'), title text not null check(length(title) between 2 and 180), sector text not null check(length(sector) between 2 and 80),
  location text not null default '', year text, size text, description text not null default '', image_url text,
  tags text[] not null default '{}', published boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.project_images (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id) on delete cascade,
  storage_path text not null, alt_text text not null default '', sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id) on delete set null,
  name text not null check(length(name) between 2 and 120), email text not null check(length(email)<=320 and email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  company text not null check(length(company) between 2 and 180), phone text not null check(length(phone) between 7 and 40),
  service text not null check(length(service) between 1 and 120), timeline text check(timeline is null or length(timeline)<=120), details text not null check(length(details) between 20 and 20000), kind text not null default 'contact' check(kind in ('contact','quote')),
  status text not null default 'new' check(status in ('new','reviewing','quoted','in_progress','completed','closed')),
  assigned_to uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create or replace function public.can_upload_inquiry(target_id uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.inquiries i where i.id=target_id and (i.user_id is null or i.user_id=auth.uid()))
$$;
revoke all on function public.can_upload_inquiry(uuid) from public;
grant execute on function public.can_upload_inquiry(uuid) to anon,authenticated;
create table if not exists public.inquiry_files (
  id uuid primary key default gen_random_uuid(), inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  storage_path text not null unique, file_name text not null, mime_type text, size_bytes bigint not null check(size_bytes between 1 and 10485760),
  created_at timestamptz not null default now()
);
create table if not exists public.quotations (
  id uuid primary key default gen_random_uuid(), inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  customer_id uuid references public.profiles(id) on delete set null, quote_number text not null unique,
  status text not null default 'draft' check(status in ('draft','sent','accepted','rejected','expired')),
  currency text not null default 'USD', subtotal numeric(14,2) not null default 0 check(subtotal>=0),
  tax_amount numeric(14,2) not null default 0 check(tax_amount>=0), total_amount numeric(14,2) not null default 0 check(total_amount>=0),
  valid_until date, notes text, document_path text, sent_at timestamptz, responded_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quotation_items (
  id uuid primary key default gen_random_uuid(), quotation_id uuid not null references public.quotations(id) on delete cascade,
  description text not null, quantity numeric(14,3) not null default 1 check(quantity>0), unit text not null default 'lot',
  unit_price numeric(14,2) not null default 0 check(unit_price>=0), amount numeric(14,2) generated always as (quantity*unit_price) stored,
  sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table if not exists public.project_updates (
  id uuid primary key default gen_random_uuid(), inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  title text not null, details text not null default '', progress_percent integer check(progress_percent between 0 and 100),
  status text not null default 'in_progress', visible_to_customer boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now()
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(), inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade, body text not null check(length(body) between 1 and 10000),
  attachment_path text, read_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.blog_posts (
  id uuid primary key default gen_random_uuid(), slug text not null unique check(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'), title text not null check(length(title) between 2 and 180), category text not null check(length(category) between 2 and 80),
  excerpt text not null default '' check(length(excerpt)<=1000), body text not null default '' check(length(body)<=50000), image_url text, author_id uuid references public.profiles(id) on delete set null,
  published boolean not null default false, published_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.testimonials (
  id uuid primary key default gen_random_uuid(), customer_name text not null, company text not null default '',
  quote text not null, rating integer not null default 5 check(rating between 1 and 5), active boolean not null default true,
  created_at timestamptz not null default now(), unique(customer_name,company)
);
create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(), name text not null, role text not null, bio text not null default '',
  image_url text, sort_order integer not null default 0, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(name,role)
);
create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(), inquiry_id uuid references public.inquiries(id) on delete set null,
  name text not null check(length(name) between 2 and 120), email text not null check(length(email)<=320 and email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'), company text check(company is null or length(company)<=180), phone text check(phone is null or length(phone)<=40), service text, timeline text,
  subject text, message text not null check(length(message) between 20 and 20000), status text not null default 'new' check(status in ('new','read','replied','closed')),
  created_at timestamptz not null default now()
);
create table if not exists public.newsletter_subscribers (
  id uuid primary key default gen_random_uuid(), email text not null unique check(length(email)<=320 and email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'), active boolean not null default true,
  subscribed_at timestamptz not null default now()
);
create table if not exists public.site_settings (
  id uuid primary key default gen_random_uuid(), key text not null unique, value jsonb not null default '{}'::jsonb,
  description text, updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create index if not exists inquiries_user_created_idx on public.inquiries(user_id,created_at desc);
create index if not exists inquiries_status_created_idx on public.inquiries(status,created_at desc);
create index if not exists inquiry_files_inquiry_idx on public.inquiry_files(inquiry_id);
create index if not exists quotations_customer_created_idx on public.quotations(customer_id,created_at desc);
create index if not exists quotations_inquiry_idx on public.quotations(inquiry_id);
create index if not exists quotation_items_quote_idx on public.quotation_items(quotation_id,sort_order);
create index if not exists project_updates_inquiry_idx on public.project_updates(inquiry_id,created_at desc);
create index if not exists messages_inquiry_created_idx on public.messages(inquiry_id,created_at);
create index if not exists projects_sector_idx on public.projects(sector,published);
create index if not exists blog_posts_published_idx on public.blog_posts(published,published_at desc);
create index if not exists contact_messages_status_idx on public.contact_messages(status,created_at desc);
create index if not exists newsletter_active_idx on public.newsletter_subscribers(active);

do $$ declare t text; begin
  foreach t in array array['profiles','services','projects','inquiries','quotations','blog_posts','team_members','site_settings'] loop
    execute format('drop trigger if exists set_updated_at on public.%I',t);
    execute format('create trigger set_updated_at before update on public.%I for each row execute procedure public.set_updated_at()',t);
  end loop;
end $$;

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.projects enable row level security;
alter table public.project_images enable row level security;
alter table public.inquiries enable row level security;
alter table public.inquiry_files enable row level security;
alter table public.quotations enable row level security;
alter table public.quotation_items enable row level security;
alter table public.project_updates enable row level security;
alter table public.messages enable row level security;
alter table public.blog_posts enable row level security;
alter table public.testimonials enable row level security;
alter table public.team_members enable row level security;
alter table public.contact_messages enable row level security;
alter table public.newsletter_subscribers enable row level security;
alter table public.site_settings enable row level security;

drop policy if exists "profiles select own or admin" on public.profiles;
create policy "profiles select own or admin" on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
drop policy if exists "profiles update own safe fields" on public.profiles;
create policy "profiles update own safe fields" on public.profiles for update to authenticated using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());
drop policy if exists "profiles admin insert" on public.profiles;
create policy "profiles admin insert" on public.profiles for insert to authenticated with check(public.is_admin());
drop policy if exists "profiles admin delete" on public.profiles;
create policy "profiles admin delete" on public.profiles for delete to authenticated using(public.is_admin());

do $$ declare t text; begin
 foreach t in array array['services','projects','project_images','blog_posts','testimonials','team_members','site_settings'] loop
   execute format('drop policy if exists "public read %1$s" on public.%1$I',t);
 end loop;
end $$;
create policy "public read services" on public.services for select to anon,authenticated using(active or public.is_admin());
create policy "public read projects" on public.projects for select to anon,authenticated using(published or public.is_admin());
create policy "public read project_images" on public.project_images for select to anon,authenticated using(exists(select 1 from public.projects p where p.id=project_id and (p.published or public.is_admin())));
create policy "public read blog_posts" on public.blog_posts for select to anon,authenticated using(published or public.is_admin());
create policy "public read testimonials" on public.testimonials for select to anon,authenticated using(active or public.is_admin());
create policy "public read team_members" on public.team_members for select to anon,authenticated using(active or public.is_admin());
create policy "public read site_settings" on public.site_settings for select to anon,authenticated using(key in ('company','branding','public_contact','site_url') or public.is_admin());

do $$ declare t text; begin
 foreach t in array array['services','projects','project_images','blog_posts','testimonials','team_members','site_settings'] loop
  execute format('drop policy if exists "admin manage %1$s" on public.%1$I',t);
  execute format('create policy "admin manage %1$s" on public.%1$I for all to authenticated using(public.is_admin()) with check(public.is_admin())',t);
 end loop;
end $$;

drop policy if exists "public create inquiries" on public.inquiries;
create policy "public create inquiries" on public.inquiries for insert to anon,authenticated with check(user_id is null or user_id=auth.uid());
drop policy if exists "customer read inquiries" on public.inquiries;
create policy "customer read inquiries" on public.inquiries for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "customer update inquiry contact" on public.inquiries;
drop policy if exists "admin update inquiries" on public.inquiries;
create policy "admin update inquiries" on public.inquiries for update to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "admin delete inquiries" on public.inquiries;
create policy "admin delete inquiries" on public.inquiries for delete to authenticated using(public.is_admin());

drop policy if exists "customer read inquiry files" on public.inquiry_files;
create policy "customer read inquiry files" on public.inquiry_files for select to authenticated using(public.is_admin() or exists(select 1 from public.inquiries i where i.id=inquiry_id and i.user_id=auth.uid()));
drop policy if exists "owner attach inquiry files" on public.inquiry_files;
create policy "owner attach inquiry files" on public.inquiry_files for insert to anon,authenticated with check(public.can_upload_inquiry(inquiry_id));
drop policy if exists "admin attach inquiry files" on public.inquiry_files;
create policy "admin attach inquiry files" on public.inquiry_files for insert to authenticated with check(public.is_admin());
drop policy if exists "admin delete inquiry files" on public.inquiry_files;
create policy "admin delete inquiry files" on public.inquiry_files for delete to authenticated using(public.is_admin());

drop policy if exists "customer read quotations" on public.quotations;
create policy "customer read quotations" on public.quotations for select to authenticated using(customer_id=auth.uid() or public.is_admin());
drop policy if exists "admin create quotations" on public.quotations;
create policy "admin create quotations" on public.quotations for insert to authenticated with check(public.is_admin());
drop policy if exists "admin or customer respond quotation" on public.quotations;
create policy "admin or customer respond quotation" on public.quotations for update to authenticated using(customer_id=auth.uid() or public.is_admin()) with check((customer_id=auth.uid() and status in ('accepted','rejected')) or public.is_admin());
drop policy if exists "admin delete quotations" on public.quotations;
create policy "admin delete quotations" on public.quotations for delete to authenticated using(public.is_admin());
drop policy if exists "customer read quotation items" on public.quotation_items;
create policy "customer read quotation items" on public.quotation_items for select to authenticated using(public.is_admin() or exists(select 1 from public.quotations q where q.id=quotation_id and q.customer_id=auth.uid()));
drop policy if exists "admin manage quotation items" on public.quotation_items;
create policy "admin manage quotation items" on public.quotation_items for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists "customer read project updates" on public.project_updates;
create policy "customer read project updates" on public.project_updates for select to authenticated using(public.is_admin() or (visible_to_customer and exists(select 1 from public.inquiries i where i.id=inquiry_id and i.user_id=auth.uid())));
drop policy if exists "admin manage project updates" on public.project_updates;
create policy "admin manage project updates" on public.project_updates for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "inquiry participants read messages" on public.messages;
create policy "inquiry participants read messages" on public.messages for select to authenticated using(public.is_admin() or exists(select 1 from public.inquiries i where i.id=inquiry_id and i.user_id=auth.uid()));
drop policy if exists "customer send inquiry message" on public.messages;
create policy "customer send inquiry message" on public.messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.inquiries i where i.id=inquiry_id and i.user_id=auth.uid()));
drop policy if exists "admin send inquiry message" on public.messages;
create policy "admin send inquiry message" on public.messages for insert to authenticated with check(public.is_admin() and sender_id=auth.uid());

drop policy if exists "public contact message insert" on public.contact_messages;
create policy "public contact message insert" on public.contact_messages for insert to anon,authenticated with check(true);
drop policy if exists "admin manage contact messages" on public.contact_messages;
create policy "admin manage contact messages" on public.contact_messages for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "public newsletter subscribe" on public.newsletter_subscribers;
create policy "public newsletter subscribe" on public.newsletter_subscribers for insert to anon,authenticated with check(length(email) between 5 and 320);
drop policy if exists "admin manage newsletter" on public.newsletter_subscribers;
create policy "admin manage newsletter" on public.newsletter_subscribers for all to authenticated using(public.is_admin()) with check(public.is_admin());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('inquiry-files','inquiry-files',false,10485760,array['application/pdf','image/png','image/jpeg','image/webp','application/acad','application/dxf','application/octet-stream']),
 ('project-media','project-media',true,20971520,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "inquiry owner upload files" on storage.objects;
create policy "inquiry owner upload files" on storage.objects for insert to anon,authenticated with check(bucket_id='inquiry-files' and storage.filename(name) ~* '[.](pdf|dwg|dxf|png|jpe?g|webp)$' and public.can_upload_inquiry(((storage.foldername(name))[1])::uuid));
drop policy if exists "admin upload inquiry files" on storage.objects;
create policy "admin upload inquiry files" on storage.objects for insert to authenticated with check(bucket_id='inquiry-files' and public.is_admin());
drop policy if exists "inquiry owner read files" on storage.objects;
create policy "inquiry owner read files" on storage.objects for select to authenticated using(bucket_id='inquiry-files' and (public.is_admin() or exists(select 1 from public.inquiries i where i.id::text=(storage.foldername(name))[1] and i.user_id=auth.uid())));
drop policy if exists "admin delete private files" on storage.objects;
create policy "admin delete private files" on storage.objects for delete to authenticated using(bucket_id in ('inquiry-files','project-media') and public.is_admin());
drop policy if exists "admin upload project media" on storage.objects;
create policy "admin upload project media" on storage.objects for insert to authenticated with check(bucket_id='project-media' and public.is_admin());
drop policy if exists "admin read project media" on storage.objects;
create policy "admin read project media" on storage.objects for select to authenticated using(bucket_id='project-media' and public.is_admin());
drop policy if exists "public read project media" on storage.objects;
create policy "public read project media" on storage.objects for select to anon,authenticated using(bucket_id='project-media');

insert into public.services(key,title,category,summary,description,image_url,icon,sort_order) values
('pipe-fabrication','Pipe Fabrication','Fabrication','Precision-built piping assemblies, ready for the field.','From carbon steel to high alloy, our fabrication teams turn engineered drawings into thoroughly inspected assemblies.','photo-1504917595217-d4dc5ebe6122','Wrench',1),
('industrial-piping-installation','Industrial Piping Installation','Installation','Safe, sequenced installation for complex live facilities.','Our field crews install process and utility piping in new builds, brownfield expansions and planned outages.','photo-1581091226825-a6a2a5aee158','Workflow',2),
('shipyard-piping','Shipyard Piping','Marine','Marine piping systems designed around tight tolerances.','We support shipyards and vessel owners with installation, modification and repair of marine piping systems.','photo-1567899378494-47b22a2ae96a','Ship',3),
('welding-services','Welding Services','Welding','Qualified welders for demanding materials and environments.','Qualified welding personnel support shop and field work across common industrial alloys and processes.','photo-1504307651254-35680f356dfd','Flame',4),
('pipe-spool-manufacturing','Pipe Spool Manufacturing','Manufacturing','Repeatable modular spool production with clear QA records.','A controlled spool production workflow aligns material receiving, cutting, fit-up, welding, dimensional checks and release documentation.','photo-1581092160562-40aa08e78837','Factory',5)
on conflict(key) do nothing;
insert into public.projects(slug,title,sector,location,year,size,description,image_url,tags) values
('gulf-coast-lng-expansion','Gulf Coast LNG Expansion','Energy','Texas, USA','2025','42,000 ft of process piping','A phased process piping package for a major LNG expansion. Shop fabrication and sequenced delivery supported installation through a tight construction window.','photo-1513828583688-c52646db42da',array['Process piping','Fabrication','Energy']),
('north-harbor-vessel-refit','North Harbor Vessel Refit','Marine','Washington, USA','2024','18 vessel systems','Coordinated renewal and testing of vessel utility and process piping through a compressed dry-dock program.','photo-1567899378494-47b22a2ae96a',array['Vessel refit','Marine','Installation']),
('riverbend-power-station','Riverbend Power Station','Power','Ontario, Canada','2024','12,500 spool inches','High-integrity auxiliary piping prefabricated and installed during a planned station outage.','photo-1473341304170-971dccb5ac1e',array['Power generation','Welding','Outage']),
('westfield-chemical-plant','Westfield Chemical Plant','Chemical','Louisiana, USA','2023','26,000 ft of utility piping','Utility piping and modular spool packages for a plant upgrade, delivered with material traceability records.','photo-1516937941344-00b4e0337589',array['Chemical','Spool manufacturing','Utilities'])
on conflict(slug) do nothing;
insert into public.blog_posts(slug,title,category,excerpt,body,image_url,published,published_at) values
('planning-a-successful-piping-outage','Planning a successful piping outage','Project delivery','A disciplined work pack starts long before the first isolation.','Plan work packs, interfaces, materials and inspection gates early to help outage teams coordinate execution.','photo-1504307651254-35680f356dfd',true,'2025-09-18T00:00:00Z'),
('spool-fabrication-and-field-productivity','How spool fabrication supports field productivity','Fabrication','Well-sequenced prefabrication can reduce site congestion and improve consistency.','A controlled prefabrication sequence helps deliver assemblies in the order the field team needs them.','photo-1581092160562-40aa08e78837',true,'2025-07-03T00:00:00Z'),
('quality-records-that-travel-with-the-work','Quality records that travel with the work','Quality & safety','Traceability works best when teams can find and understand the records.','A clear turnover package connects material traceability, inspection evidence and the installed system.','photo-1581091226825-a6a2a5aee158',true,'2025-04-22T00:00:00Z')
on conflict(slug) do nothing;
insert into public.team_members(name,role,bio,image_url,sort_order) values
('Elena Vasquez','Chief Executive Officer','Builds strong project partnerships and keeps safety and delivery at the center of our work.','photo-1580489944761-15a19d654956',1),
('Marcus Chen','VP, Operations','Leads shop and field teams across complex industrial and marine scopes.','photo-1500648767791-00dcc994a43e',2),
('Aisha Rahman','Director, Quality','Champions a practical quality culture from material receipt to project turnover.','photo-1551836022-d5d88e9218df',3)
on conflict do nothing;
insert into public.testimonials(customer_name,company,quote,rating) values
('Jordan Mills','Northshore Process','Their field team understood the outage constraints and kept communication direct from planning through turnover.',5),
('Morgan Patel','Harbor Works','The spool packages arrived sequenced and the documentation was easy for our team to follow.',5),
('Taylor Brooks','Riverbend Energy','A safety-minded crew that took ownership of the details across a demanding schedule.',5)
on conflict do nothing;
insert into public.site_settings(key,value,description) values
('company',jsonb_build_object('name','PipeMaster Engineering','email','projects@pipemaster.example','phone','+1 713 555 0148','address','Houston, Texas, United States'),'Public company contact information')
on conflict(key) do nothing;
