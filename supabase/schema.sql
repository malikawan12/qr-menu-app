create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null default 'La Tavola',
  tagline text not null default 'Casa Italiana',
  open_until time not null default '23:00',
  menu_slug text not null unique default encode(gen_random_bytes(8), 'hex'),
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (restaurant_id, name)
);

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name text not null,
  description text not null default '',
  price numeric(10,2) not null check (price >= 0),
  category text not null,
  image_url text not null,
  is_popular boolean not null default false,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_deals (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name text not null,
  description text not null default '',
  price numeric(10,2) not null check (price >= 0),
  old_price numeric(10,2),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (restaurant_id)
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  tracking_token text not null unique default encode(gen_random_bytes(16), 'hex'),
  status text not null default 'New' check (status in ('New', 'Preparing', 'Ready', 'Delivered', 'Completed', 'Cancelled')),
  total numeric(10,2) not null check (total >= 0),
  created_at timestamptz not null default now()
);

do $$
begin
  alter table public.orders drop constraint if exists orders_status_check;
  alter table public.orders add constraint orders_status_check check (status in ('New', 'Preparing', 'Ready', 'Delivered', 'Completed', 'Cancelled'));
exception when undefined_table then
  null;
end $$;

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  item_name text not null,
  unit_price numeric(10,2) not null check (unit_price >= 0),
  quantity integer not null default 1 check (quantity > 0)
);

do $$
begin
  alter table public.menu_items drop constraint if exists menu_items_category_check;
exception when undefined_table then
  null;
end $$;

create index if not exists menu_items_restaurant_idx on public.menu_items(restaurant_id);
create index if not exists categories_restaurant_idx on public.categories(restaurant_id, sort_order);
create index if not exists orders_restaurant_idx on public.orders(restaurant_id, created_at desc);
create index if not exists orders_tracking_idx on public.orders(tracking_token);

do $$
begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then
  null;
end $$;

alter table public.profiles enable row level security;
alter table public.restaurants enable row level security;
alter table public.categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.daily_deals enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

create or replace function public.is_restaurant_owner(target_restaurant uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.restaurants where id = target_restaurant and owner_id = auth.uid());
$$;

drop policy if exists "profiles are private to their owner" on public.profiles;
drop policy if exists "owners can update their profile" on public.profiles;
drop policy if exists "owners can manage their restaurants" on public.restaurants;
drop policy if exists "owners manage menu items" on public.menu_items;
drop policy if exists "owners manage categories" on public.categories;
drop policy if exists "customers read categories" on public.categories;
drop policy if exists "customers read published menu items" on public.menu_items;
drop policy if exists "owners manage daily deals" on public.daily_deals;
drop policy if exists "customers read active deals" on public.daily_deals;
drop policy if exists "owners read and update orders" on public.orders;
drop policy if exists "owners update orders" on public.orders;
drop policy if exists "customers create orders" on public.orders;
drop policy if exists "owners read order items" on public.order_items;
drop policy if exists "customers create order items" on public.order_items;

create policy "profiles are private to their owner" on public.profiles for select using (id = auth.uid());
create policy "owners can update their profile" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
create policy "owners can manage their restaurants" on public.restaurants for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "owners manage menu items" on public.menu_items for all using (public.is_restaurant_owner(restaurant_id)) with check (public.is_restaurant_owner(restaurant_id));
create policy "owners manage categories" on public.categories for all using (public.is_restaurant_owner(restaurant_id)) with check (public.is_restaurant_owner(restaurant_id));
create policy "customers read categories" on public.categories for select using (exists (select 1 from public.restaurants r where r.id = restaurant_id));
create policy "customers read published menu items" on public.menu_items for select using (is_published and exists (select 1 from public.restaurants r where r.id = restaurant_id));
create policy "owners manage daily deals" on public.daily_deals for all using (public.is_restaurant_owner(restaurant_id)) with check (public.is_restaurant_owner(restaurant_id));
create policy "customers read active deals" on public.daily_deals for select using (active);
create policy "owners read and update orders" on public.orders for select using (public.is_restaurant_owner(restaurant_id));
create policy "owners update orders" on public.orders for update using (public.is_restaurant_owner(restaurant_id)) with check (public.is_restaurant_owner(restaurant_id));
create policy "customers create orders" on public.orders for insert with check (exists (select 1 from public.restaurants r where r.id = restaurant_id));
create policy "owners read order items" on public.order_items for select using (exists (select 1 from public.orders o where o.id = order_id and public.is_restaurant_owner(o.restaurant_id)));
create policy "customers create order items" on public.order_items for insert with check (exists (select 1 from public.orders o where o.id = order_id));

create or replace function public.get_public_restaurant(restaurant_menu_slug text)
returns table (id uuid, name text, tagline text, open_until time, menu_slug text)
language sql stable security definer set search_path = public as $$
  select r.id, r.name, r.tagline, r.open_until, r.menu_slug
  from public.restaurants r
  where r.menu_slug = restaurant_menu_slug;
$$;
grant execute on function public.get_public_restaurant(text) to anon, authenticated;

create or replace function public.create_customer_order(
  target_restaurant uuid,
  order_total numeric,
  order_items jsonb
)
returns table (id uuid, tracking_token text, status text, total numeric, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  created_order public.orders;
begin
  if not exists (select 1 from public.restaurants where public.restaurants.id = target_restaurant) then
    raise exception 'Restaurant not found';
  end if;
  if order_total <= 0 or jsonb_array_length(order_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;
  insert into public.orders (restaurant_id, total)
  values (target_restaurant, order_total)
  returning * into created_order;
  insert into public.order_items (order_id, menu_item_id, item_name, unit_price, quantity)
  select created_order.id, item.menu_item_id, item.item_name, item.unit_price, item.quantity
  from jsonb_to_recordset(order_items) as item(menu_item_id uuid, item_name text, unit_price numeric, quantity integer);
  return query select created_order.id, created_order.tracking_token, created_order.status, created_order.total, created_order.created_at;
end;
$$;
grant execute on function public.create_customer_order(uuid, numeric, jsonb) to anon, authenticated;

insert into storage.buckets (id, name, public)
values ('restaurant-images', 'restaurant-images', true)
on conflict (id) do nothing;

drop policy if exists "owners upload restaurant images" on storage.objects;
drop policy if exists "owners update restaurant images" on storage.objects;
drop policy if exists "owners delete restaurant images" on storage.objects;
drop policy if exists "public read restaurant images" on storage.objects;
create policy "owners upload restaurant images" on storage.objects for insert to authenticated
with check (bucket_id = 'restaurant-images' and public.is_restaurant_owner((storage.foldername(name))[1]::uuid));
create policy "owners update restaurant images" on storage.objects for update to authenticated
using (bucket_id = 'restaurant-images' and public.is_restaurant_owner((storage.foldername(name))[1]::uuid));
create policy "owners delete restaurant images" on storage.objects for delete to authenticated
using (bucket_id = 'restaurant-images' and public.is_restaurant_owner((storage.foldername(name))[1]::uuid));
create policy "public read restaurant images" on storage.objects for select to anon, authenticated
using (bucket_id = 'restaurant-images');

create or replace function public.get_order_status(order_tracking_token text)
returns table (id uuid, status text, total numeric, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select o.id, o.status, o.total, o.created_at from public.orders o where o.tracking_token = order_tracking_token;
$$;
grant execute on function public.get_order_status(text) to anon, authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name) values (new.id, new.raw_user_meta_data ->> 'full_name');
  insert into public.restaurants (owner_id, name, tagline) values (new.id, coalesce(new.raw_user_meta_data ->> 'restaurant_name', 'La Tavola'), 'Casa Italiana');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

notify pgrst, 'reload schema';
