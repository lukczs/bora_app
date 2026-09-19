-- =====================================================================
-- BORA — schema completo (Supabase / Postgres)
-- Rode este arquivo inteiro, uma vez, no SQL Editor de um projeto NOVO.
-- Substitui os arquivos anteriores (bora_schema.sql, 0002, 0003).
--
-- Decisões desta versão:
--  * Sem PostGIS: paradas guardam lat/lng e a distância usa haversine.
--    Menos dependências agora; migrar para PostGIS depois é simples.
--  * O trajeto é calculado no app sobre o grafo de paradas (stop_links) e
--    VALIDADO aqui. Quando entrar uma API de rotas, só publish_ride muda.
--  * Sem pagamento no app: o valor é o rateio sugerido, pago ao motorista.
--  * Quase toda leitura passa por funções (security definer) que devolvem
--    JSON já filtrado. As tabelas ficam fechadas por RLS.
-- =====================================================================

-- ---------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------
create type gender              as enum ('female', 'male', 'other');
create type verification_status as enum ('pending', 'in_review', 'approved', 'rejected');
create type ride_status         as enum ('open', 'in_progress', 'completed', 'cancelled');
create type booking_status      as enum ('reserved', 'boarded', 'completed', 'cancelled');
create type ride_visibility     as enum ('public', 'communities');
create type community_kind      as enum ('education', 'company', 'residential', 'corridor', 'group');
create type community_join      as enum ('invite_code', 'approval');
create type member_role         as enum ('owner', 'admin', 'member');
create type member_status       as enum ('pending', 'active', 'banned');

-- ---------------------------------------------------------------------
-- CONFIGURAÇÃO (uma linha só)
-- ---------------------------------------------------------------------
create table app_config (
  id                     boolean primary key default true check (id),
  auto_approve_identity  boolean not null default true,  -- DEV: aprova na hora. Em produção: false + painel admin
  rate_per_km_cents      int not null default 20,
  min_price_cents        int not null default 400,
  rounding_cents         int not null default 50
);
insert into app_config default values;

-- ---------------------------------------------------------------------
-- USUÁRIOS
-- ---------------------------------------------------------------------
create table profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  phone           text,
  full_name       text,
  cpf             text unique,
  birth_date      date,
  gender          gender,
  identity_status verification_status not null default 'pending',
  women_only_pref boolean not null default false,
  onboarding_done boolean not null default false,
  rating_avg      numeric(3,2) not null default 0,
  rating_count    int not null default 0,
  created_at      timestamptz not null default now(),
  constraint women_only_pref_requires_female check (not women_only_pref or gender = 'female')
);

create table emergency_contacts (
  user_id  uuid primary key references profiles (id) on delete cascade,
  name     text not null,
  phone    text not null,
  relation text not null
);

create table vehicles (
  id       uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references profiles (id) on delete cascade,
  plate    text not null unique,
  brand    text not null,
  model    text not null,
  color    text not null,
  seats    int  not null check (seats between 1 and 6)
);
create index on vehicles (owner_id);

-- ---------------------------------------------------------------------
-- PARADAS E GRAFO
-- ---------------------------------------------------------------------
create table stops (
  id        text primary key,
  name      text not null,
  region    text not null,
  lat       double precision not null,
  lng       double precision not null,
  boardable boolean not null default true,   -- false = ponto de passagem, só desenha a rota
  active    boolean not null default true
);

create table stop_links (
  a text not null references stops (id),
  b text not null references stops (id),
  primary key (a, b),
  check (a <> b)
);

-- ---------------------------------------------------------------------
-- COMUNIDADES
-- ---------------------------------------------------------------------
create table communities (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (char_length(name) between 3 and 60),
  description    text not null default '',
  kind           community_kind not null default 'group',
  join_mode      community_join not null default 'invite_code',
  invite_code    text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)),
  anchor_stop_id text references stops (id),
  created_by     uuid not null references profiles (id),
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

create table community_members (
  community_id uuid not null references communities (id) on delete cascade,
  user_id      uuid not null references profiles (id) on delete cascade,
  role         member_role   not null default 'member',
  status       member_status not null default 'active',
  joined_at    timestamptz   not null default now(),
  primary key (community_id, user_id)
);
create index on community_members (user_id);

-- ---------------------------------------------------------------------
-- VIAGENS E RESERVAS
-- ---------------------------------------------------------------------
create table rides (
  id              uuid primary key default gen_random_uuid(),
  driver_id       uuid not null references profiles (id),
  vehicle_id      uuid not null references vehicles (id),
  path            text[] not null,               -- ids das paradas, na ordem do trajeto
  distance_m      int not null,
  departure_at    timestamptz not null,
  recurring_days  int[] not null default '{}',   -- 1 = segunda ... 7 = domingo
  seats_total     int not null check (seats_total between 1 and 6),
  seats_available int not null check (seats_available >= 0),
  women_only      boolean not null default false,
  visibility      ride_visibility not null default 'public',
  status          ride_status not null default 'open',
  created_at      timestamptz not null default now(),
  check (seats_available <= seats_total)
);
create index on rides (driver_id);
create index on rides (status, departure_at);

create table ride_stops (
  ride_id               uuid not null references rides (id) on delete cascade,
  stop_id               text not null references stops (id),
  seq                   int  not null,
  distance_from_start_m int  not null,
  primary key (ride_id, stop_id)
);
create index on ride_stops (stop_id);

create table ride_communities (
  ride_id      uuid not null references rides (id) on delete cascade,
  community_id uuid not null references communities (id) on delete cascade,
  primary key (ride_id, community_id)
);

create table bookings (
  id              uuid primary key default gen_random_uuid(),
  ride_id         uuid not null references rides (id),
  passenger_id    uuid not null references profiles (id),
  pickup_stop_id  text not null references stops (id),
  dropoff_stop_id text not null references stops (id),
  distance_m      int  not null,
  price_cents     int  not null,                 -- congelado na reserva
  boarding_code   text not null,
  status          booking_status not null default 'reserved',
  created_at      timestamptz not null default now()
);
create index on bookings (ride_id);
create index on bookings (passenger_id);
create unique index bookings_one_active_per_ride
  on bookings (ride_id, passenger_id) where status in ('reserved', 'boarded');

-- Buscas sem resultado: onde existe demanda sem oferta
create table unmet_searches (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references profiles (id) on delete cascade,
  pickup     text not null references stops (id),
  dropoff    text not null references stops (id),
  created_at timestamptz not null default now()
);

-- =====================================================================
-- FUNÇÕES AUXILIARES
-- =====================================================================

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, phone) values (new.id, new.phone);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Distância em metros entre dois pontos (haversine)
create or replace function meters_between(lat1 double precision, lng1 double precision,
                                          lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

-- Distância "por estrada" entre duas paradas ligadas (fator 1,25 sobre a linha reta)
create or replace function link_meters(p_a text, p_b text) returns int
language sql stable set search_path = public as $$
  select (meters_between(a.lat, a.lng, b.lat, b.lng) * 1.25)::int
  from stops a, stops b where a.id = p_a and b.id = p_b;
$$;

create or replace function compute_price(p_distance_m int) returns int
language sql stable set search_path = public as $$
  select greatest(c.min_price_cents,
                  (round((p_distance_m / 1000.0 * c.rate_per_km_cents) / c.rounding_cents) * c.rounding_cents)::int)
  from app_config c;
$$;

create or replace function is_community_member(p_community uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from community_members
                  where community_id = p_community and user_id = p_user and status = 'active');
$$;

create or replace function can_access_ride(p_ride uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from rides r
     where r.id = p_ride
       and (r.visibility = 'public' or r.driver_id = p_user
            or exists (select 1 from ride_communities rc
                        where rc.ride_id = r.id and is_community_member(rc.community_id, p_user))));
$$;

create or replace function shared_communities(p_a uuid, p_b uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.name order by c.name), '{}')
  from communities c
  where c.active and is_community_member(c.id, p_a) and is_community_member(c.id, p_b);
$$;

-- O que uma pessoa pode ver de outra: nada de CPF, telefone ou data de nascimento
create or replace function person_json(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', id, 'full_name', full_name, 'gender', gender,
                            'rating_avg', rating_avg, 'rating_count', rating_count)
  from profiles where id = p_user;
$$;

create or replace function vehicle_json(p_vehicle uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(v) from vehicles v where v.id = p_vehicle;
$$;

create or replace function ride_json(p_ride uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(r)
      || jsonb_build_object(
           'driver',  person_json(r.driver_id),
           'vehicle', vehicle_json(r.vehicle_id),
           'communities', coalesce((
              select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
              from ride_communities rc join communities c on c.id = rc.community_id
              where rc.ride_id = r.id), '[]'::jsonb))
  from rides r where r.id = p_ride;
$$;

-- =====================================================================
-- CADASTRO
-- =====================================================================

create or replace function my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(p) || jsonb_build_object(
           'emergency_contact', (select to_jsonb(e) from emergency_contacts e where e.user_id = p.id))
  from profiles p where p.id = auth.uid();
$$;

create or replace function submit_registration(
  p_full_name text, p_cpf text, p_birth_date date, p_gender gender, p_women_only_pref boolean
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_cpf !~ '^\d{11}$' then raise exception 'invalid_cpf'; end if;
  if p_birth_date > (current_date - interval '18 years') then raise exception 'must_be_adult'; end if;

  update profiles
     set full_name = trim(p_full_name), cpf = p_cpf, birth_date = p_birth_date, gender = p_gender,
         women_only_pref = (p_gender = 'female' and coalesce(p_women_only_pref, false))
   where id = auth.uid() and identity_status in ('pending', 'rejected');
  if not found then raise exception 'identity_locked'; end if;
exception
  when unique_violation then raise exception 'cpf_already_registered';
end $$;

create or replace function save_emergency_contact(p_name text, p_phone text, p_relation text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into emergency_contacts (user_id, name, phone, relation)
  values (auth.uid(), trim(p_name), p_phone, p_relation)
  on conflict (user_id) do update set name = excluded.name, phone = excluded.phone, relation = excluded.relation;
end $$;

-- Envio de documento + selfie. Com auto_approve_identity aprova na hora (DEV).
create or replace function submit_identity_documents() returns verification_status
language plpgsql security definer set search_path = public as $$
declare v_status verification_status;
begin
  select case when auto_approve_identity then 'approved' else 'in_review' end::verification_status
    into v_status from app_config;
  update profiles set identity_status = v_status
   where id = auth.uid() and identity_status in ('pending', 'rejected');
  if not found then raise exception 'identity_locked'; end if;
  return v_status;
end $$;

create or replace function finish_onboarding() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and full_name is not null and cpf is not null)
    then raise exception 'registration_incomplete'; end if;
  if not exists (select 1 from emergency_contacts where user_id = auth.uid())
    then raise exception 'emergency_contact_required'; end if;
  update profiles set onboarding_done = true where id = auth.uid();
end $$;

-- =====================================================================
-- VIAGENS
-- =====================================================================

create or replace function publish_ride(
  p_vehicle uuid, p_path text[], p_departure timestamptz, p_seats int,
  p_recurring int[], p_women_only boolean, p_communities uuid[]
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; v_vehicle vehicles; v_ride uuid;
  v_total int := 0; v_n int := coalesce(array_length(p_path, 1), 0); v_c uuid;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  if v_me.identity_status <> 'approved' then raise exception 'identity_not_verified'; end if;
  if p_women_only and v_me.gender is distinct from 'female' then raise exception 'women_only_not_allowed'; end if;

  select * into v_vehicle from vehicles where id = p_vehicle and owner_id = v_me.id;
  if v_vehicle.id is null then raise exception 'vehicle_not_found'; end if;
  if p_seats < 1 or p_seats > v_vehicle.seats then raise exception 'invalid_seats'; end if;
  if p_departure < now() - interval '5 minutes' then raise exception 'departure_in_past'; end if;

  -- valida o trajeto: paradas existem, pontas embarcáveis, vizinhos ligados no grafo
  if v_n < 2 then raise exception 'invalid_path'; end if;
  if (select count(*) from stops where id = any (p_path) and active) <> v_n then raise exception 'invalid_path'; end if;
  if not (select boardable from stops where id = p_path[1])
     or not (select boardable from stops where id = p_path[v_n]) then raise exception 'invalid_path'; end if;
  for i in 1 .. v_n - 1 loop
    if not exists (select 1 from stop_links
                    where (a = p_path[i] and b = p_path[i + 1]) or (a = p_path[i + 1] and b = p_path[i]))
      then raise exception 'invalid_path'; end if;
  end loop;

  if p_communities is not null then
    foreach v_c in array p_communities loop
      if not is_community_member(v_c, v_me.id) then raise exception 'not_a_member'; end if;
    end loop;
  end if;

  insert into rides (driver_id, vehicle_id, path, distance_m, departure_at, recurring_days,
                     seats_total, seats_available, women_only, visibility)
  values (v_me.id, p_vehicle, p_path, 0, p_departure, coalesce(p_recurring, '{}'),
          p_seats, p_seats, coalesce(p_women_only, false),
          case when coalesce(array_length(p_communities, 1), 0) > 0
               then 'communities'::ride_visibility else 'public'::ride_visibility end)
  returning id into v_ride;

  for i in 1 .. v_n loop
    if i > 1 then v_total := v_total + link_meters(p_path[i - 1], p_path[i]); end if;
    insert into ride_stops (ride_id, stop_id, seq, distance_from_start_m) values (v_ride, p_path[i], i, v_total);
  end loop;
  update rides set distance_m = v_total where id = v_ride;

  if p_communities is not null then
    insert into ride_communities (ride_id, community_id) select v_ride, unnest(p_communities);
  end if;
  return v_ride;
end $$;

create or replace function update_ride(p_ride uuid, p_departure timestamptz, p_seats int, p_recurring int[])
returns void language plpgsql security definer set search_path = public as $$
declare v_ride rides; v_taken int; v_max int;
begin
  select * into v_ride from rides where id = p_ride and driver_id = auth.uid() and status = 'open' for update;
  if v_ride.id is null then raise exception 'not_allowed'; end if;
  v_taken := v_ride.seats_total - v_ride.seats_available;
  select seats into v_max from vehicles where id = v_ride.vehicle_id;
  if p_seats < v_taken then raise exception 'seats_below_booked'; end if;
  if p_seats > v_max then raise exception 'invalid_seats'; end if;
  update rides set departure_at = p_departure, recurring_days = coalesce(p_recurring, '{}'),
                   seats_total = p_seats, seats_available = p_seats - v_taken
   where id = p_ride;
end $$;

create or replace function cancel_ride(p_ride uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update rides set status = 'cancelled'
   where id = p_ride and driver_id = auth.uid() and status = 'open';
  if not found then raise exception 'not_allowed'; end if;
  update bookings set status = 'cancelled' where ride_id = p_ride and status = 'reserved';
end $$;

-- Viagens que eu ofereço, com passageiros
create or replace function my_rides() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(
           ride_json(r.id) || jsonb_build_object('bookings', coalesce((
             select jsonb_agg(to_jsonb(b) - 'boarding_code'
                      || jsonb_build_object(
                           'passenger', person_json(b.passenger_id),
                           'shared_communities', to_jsonb(shared_communities(r.driver_id, b.passenger_id)))
                      order by b.created_at)
             from bookings b where b.ride_id = r.id and b.status <> 'cancelled'), '[]'::jsonb))
           order by r.departure_at), '[]'::jsonb)
  from rides r where r.driver_id = auth.uid();
$$;

-- Viagens abertas que eu posso ver (para o mapa: quantas passam em cada parada)
create or replace function open_rides_overview() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'path', r.path)), '[]'::jsonb)
  from rides r
  where r.status = 'open' and r.seats_available > 0 and r.departure_at > now() - interval '1 hour'
    and can_access_ride(r.id, auth.uid());
$$;

create or replace function search_rides(p_pickup text, p_dropoff text, p_only_my_communities boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me profiles; v_result jsonb;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;

  select coalesce(jsonb_agg(o.offer order by o.has_shared desc, o.departure_at), '[]'::jsonb) into v_result
  from (
    select jsonb_build_object(
             'ride', ride_json(r.id),
             'pickup_stop_id', p_pickup, 'dropoff_stop_id', p_dropoff,
             'distance_m', b.distance_from_start_m - a.distance_from_start_m,
             'price_cents', compute_price(b.distance_from_start_m - a.distance_from_start_m),
             'shared_communities', to_jsonb(shared_communities(v_me.id, r.driver_id))) as offer,
           cardinality(shared_communities(v_me.id, r.driver_id)) > 0 as has_shared,
           r.departure_at
    from rides r
    join ride_stops a on a.ride_id = r.id and a.stop_id = p_pickup
    join ride_stops b on b.ride_id = r.id and b.stop_id = p_dropoff
    join profiles d   on d.id = r.driver_id
    where r.status = 'open' and r.seats_available > 0
      and r.departure_at > now() - interval '1 hour'
      and a.seq < b.seq
      and r.driver_id <> v_me.id
      and can_access_ride(r.id, v_me.id)
      and (not r.women_only        or v_me.gender = 'female')
      and (not v_me.women_only_pref or d.gender = 'female')
      and (not p_only_my_communities or cardinality(shared_communities(v_me.id, r.driver_id)) > 0)
  ) o;

  if v_result = '[]'::jsonb then
    insert into unmet_searches (user_id, pickup, dropoff) values (v_me.id, p_pickup, p_dropoff);
  end if;
  return v_result;
end $$;

-- =====================================================================
-- RESERVAS
-- =====================================================================

create or replace function book_seat(p_ride uuid, p_pickup text, p_dropoff text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; v_ride rides; v_driver_gender gender;
  v_a ride_stops; v_b ride_stops; v_distance int; v_id uuid;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;

  select * into v_ride from rides where id = p_ride for update;   -- trava: duas pessoas, uma vaga
  if v_ride.id is null or v_ride.status <> 'open' then raise exception 'ride_unavailable'; end if;
  if v_ride.driver_id = v_me.id then raise exception 'cannot_book_own_ride'; end if;
  if not can_access_ride(p_ride, v_me.id) then raise exception 'ride_unavailable'; end if;
  if v_ride.seats_available < 1 then raise exception 'ride_full'; end if;
  if v_me.identity_status <> 'approved' then raise exception 'identity_not_verified'; end if;
  if not exists (select 1 from emergency_contacts where user_id = v_me.id)
    then raise exception 'emergency_contact_required'; end if;

  select gender into v_driver_gender from profiles where id = v_ride.driver_id;
  if v_ride.women_only and v_me.gender is distinct from 'female' then raise exception 'women_only_ride'; end if;
  if v_me.women_only_pref and v_driver_gender is distinct from 'female'
    then raise exception 'driver_not_allowed_by_preference'; end if;

  if exists (select 1 from bookings where ride_id = p_ride and passenger_id = v_me.id
                                      and status in ('reserved', 'boarded'))
    then raise exception 'already_booked'; end if;

  select * into v_a from ride_stops where ride_id = p_ride and stop_id = p_pickup;
  select * into v_b from ride_stops where ride_id = p_ride and stop_id = p_dropoff;
  if v_a.ride_id is null or v_b.ride_id is null or v_a.seq >= v_b.seq then raise exception 'stops_not_on_route'; end if;

  v_distance := v_b.distance_from_start_m - v_a.distance_from_start_m;
  insert into bookings (ride_id, passenger_id, pickup_stop_id, dropoff_stop_id, distance_m, price_cents, boarding_code)
  values (p_ride, v_me.id, p_pickup, p_dropoff, v_distance, compute_price(v_distance),
          lpad(floor(random() * 10000)::int::text, 4, '0'))
  returning id into v_id;

  update rides set seats_available = seats_available - 1 where id = p_ride;
  return v_id;
end $$;

create or replace function cancel_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_b bookings;
begin
  select * into v_b from bookings where id = p_booking and passenger_id = auth.uid() for update;
  if v_b.id is null or v_b.status <> 'reserved' then raise exception 'cannot_cancel'; end if;
  update bookings set status = 'cancelled' where id = p_booking;
  update rides set seats_available = seats_available + 1
   where id = v_b.ride_id and status in ('open', 'in_progress');
end $$;

create or replace function my_bookings() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(b) || jsonb_build_object('ride', ride_json(b.ride_id))
                            order by b.created_at desc), '[]'::jsonb)
  from bookings b where b.passenger_id = auth.uid();
$$;

-- =====================================================================
-- COMUNIDADES
-- =====================================================================

create or replace function my_communities() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
           'my_role', m.role, 'my_status', m.status,
           'member_count', (select count(*) from community_members x
                             where x.community_id = c.id and x.status = 'active'))
           order by c.name), '[]'::jsonb)
  from community_members m join communities c on c.id = m.community_id
  where m.user_id = auth.uid() and m.status in ('active', 'pending') and c.active;
$$;

create or replace function create_community(
  p_name text, p_description text, p_kind community_kind, p_join_mode community_join, p_anchor_stop text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists (select 1 from profiles where id = auth.uid() and identity_status = 'approved')
    then raise exception 'identity_not_verified'; end if;
  if (select count(*) from communities where created_by = auth.uid() and active) >= 3
    then raise exception 'community_limit_reached'; end if;

  insert into communities (name, description, kind, join_mode, anchor_stop_id, created_by)
  values (trim(p_name), coalesce(trim(p_description), ''), p_kind, p_join_mode, p_anchor_stop, auth.uid())
  returning id into v_id;
  insert into community_members (community_id, user_id, role) values (v_id, auth.uid(), 'owner');
  return v_id;
end $$;

-- Devolve 'active' ou 'pending'
create or replace function join_community(p_invite_code text) returns member_status
language plpgsql security definer set search_path = public as $$
declare v_c communities; v_status member_status;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v_c from communities where invite_code = upper(trim(p_invite_code)) and active;
  if v_c.id is null then raise exception 'invalid_invite_code'; end if;

  select status into v_status from community_members where community_id = v_c.id and user_id = auth.uid();
  if v_status = 'banned' then raise exception 'banned_from_community'; end if;
  if v_status is not null then return v_status; end if;

  v_status := case when v_c.join_mode = 'approval' then 'pending' else 'active' end;
  insert into community_members (community_id, user_id, status) values (v_c.id, auth.uid(), v_status);
  return v_status;
end $$;

create or replace function leave_community(p_community uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from community_members
              where community_id = p_community and user_id = auth.uid() and role = 'owner')
    then raise exception 'owner_cannot_leave'; end if;
  delete from community_members where community_id = p_community and user_id = auth.uid();
end $$;

create or replace function community_members_list(p_community uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_community_member(p_community, auth.uid()) then raise exception 'not_a_member'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
                   'person', person_json(m.user_id), 'role', m.role, 'status', m.status)
                   order by m.role, m.joined_at), '[]'::jsonb)
          from community_members m where m.community_id = p_community and m.status <> 'banned');
end $$;

create or replace function set_member_status(p_community uuid, p_user uuid, p_status member_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from community_members
                  where community_id = p_community and user_id = auth.uid()
                    and status = 'active' and role in ('owner', 'admin'))
    then raise exception 'not_allowed'; end if;
  update community_members set status = p_status
   where community_id = p_community and user_id = p_user and role <> 'owner';
  if not found then raise exception 'member_not_found'; end if;
end $$;

-- =====================================================================
-- RLS: tabelas fechadas; só o que o app lê direto tem policy
-- =====================================================================
alter table app_config         enable row level security;
alter table profiles           enable row level security;
alter table emergency_contacts enable row level security;
alter table vehicles           enable row level security;
alter table stops              enable row level security;
alter table stop_links         enable row level security;
alter table communities        enable row level security;
alter table community_members  enable row level security;
alter table rides              enable row level security;
alter table ride_stops         enable row level security;
alter table ride_communities   enable row level security;
alter table bookings           enable row level security;
alter table unmet_searches     enable row level security;

create policy "read config"     on app_config for select to authenticated using (true);
create policy "read stops"      on stops      for select to authenticated using (active);
create policy "read stop links" on stop_links for select to authenticated using (true);
create policy "own vehicles"    on vehicles   for all    to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Funções: só para quem está logado
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

-- Papéis internos do Supabase (o gatilho de novo usuário roda como supabase_auth_admin)
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function handle_new_user() to supabase_auth_admin;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on all functions in schema public to service_role;
  end if;
end $$;

-- =====================================================================
-- DADOS INICIAIS: paradas e ligações (coordenadas aproximadas)
-- =====================================================================
insert into stops (id, name, region, lat, lng, boardable) values
  ('rod_plano',      'Rodoviária do Plano Piloto',          'Plano Piloto', -15.7938, -47.8828, true),
  ('w3_sul_903',     'W3 Sul 703/903',                      'Asa Sul',      -15.8105, -47.9010, true),
  ('scs',            'Setor Comercial Sul',                 'Plano Piloto', -15.7975, -47.8890, true),
  ('eixo_n_108',     'Eixo Norte 108',                      'Asa Norte',    -15.7640, -47.8830, true),
  ('unb',            'UnB (L3 Norte)',                      'Asa Norte',    -15.7632, -47.8706, true),
  ('eixo_n_116',     'Eixo Norte 116',                      'Asa Norte',    -15.7395, -47.8835, true),
  ('wp_bragueto',    'Ponte do Bragueto',                   'BR-020',       -15.7265, -47.8790, false),
  ('colorado',       'Balão do Colorado',                   'Sobradinho',   -15.6905, -47.8350, true),
  ('sobradinho_2',   'Sobradinho II (AR 13)',               'Sobradinho II',-15.6420, -47.8200, true),
  ('rod_sobradinho', 'Rodoviária de Sobradinho',            'Sobradinho',   -15.6530, -47.7910, true),
  ('sobradinho_q8',  'Sobradinho Quadra 8',                 'Sobradinho',   -15.6475, -47.7840, true),
  ('wp_br020_a',     'BR-020 km 18',                        'BR-020',       -15.6420, -47.7400, false),
  ('wp_br020_b',     'BR-020 km 25',                        'BR-020',       -15.6300, -47.6950, false),
  ('planaltina_ent', 'Entrada de Planaltina',               'Planaltina',   -15.6235, -47.6700, true),
  ('rod_planaltina', 'Rodoviária de Planaltina',            'Planaltina',   -15.6210, -47.6520, true),
  ('arapoanga',      'Arapoanga (Av. Principal)',           'Planaltina',   -15.6420, -47.6480, true),
  ('sig',            'SIG Quadra 1',                        'Plano Piloto', -15.7935, -47.9150, true),
  ('octogonal',      'EPTG Octogonal',                      'Cruzeiro',     -15.8050, -47.9400, true),
  ('guara',          'EPTG Guará',                          'Guará',        -15.8150, -47.9800, true),
  ('aguas_claras',   'Águas Claras (Estação Arniqueiras)',  'Águas Claras', -15.8340, -48.0260, true),
  ('taguatinga',     'Taguatinga Centro',                   'Taguatinga',   -15.8330, -48.0560, true),
  ('ceilandia',      'Ceilândia Centro',                    'Ceilândia',    -15.8190, -48.1080, true);

insert into stop_links (a, b) values
  ('w3_sul_903', 'scs'), ('scs', 'rod_plano'), ('rod_plano', 'eixo_n_108'), ('eixo_n_108', 'eixo_n_116'),
  ('eixo_n_116', 'wp_bragueto'), ('wp_bragueto', 'colorado'), ('colorado', 'rod_sobradinho'),
  ('rod_sobradinho', 'sobradinho_q8'), ('sobradinho_q8', 'wp_br020_a'), ('wp_br020_a', 'wp_br020_b'),
  ('wp_br020_b', 'planaltina_ent'), ('planaltina_ent', 'rod_planaltina'), ('rod_planaltina', 'arapoanga'),
  ('eixo_n_108', 'unb'), ('colorado', 'sobradinho_2'),
  ('rod_plano', 'sig'), ('sig', 'octogonal'), ('octogonal', 'guara'), ('guara', 'aguas_claras'),
  ('aguas_claras', 'taguatinga'), ('taguatinga', 'ceilandia');
