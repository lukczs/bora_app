-- =====================================================================
-- BORA — 0002: carona universitária
-- (reconstruído a partir do banco em produção; já está aplicado no
--  projeto "bora" do Supabase. Só rode num projeto novo.)
--
--  * Motorista pode remover passageiro (com motivo opcional)
--  * Chat em tempo real por viagem (Supabase Realtime + RLS)
--  * Comunidades com verificação por e-mail institucional
--  * keep_alive() para o GitHub Actions não deixar o projeto pausar
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- Ajustes em tabelas existentes
-- ---------------------------------------------------------------------
alter type community_join add value if not exists 'email_domain';

alter table app_config
  add column if not exists email_dev_echo boolean not null default true,      -- DEV: devolve o código na resposta
  add column if not exists email_from     text    not null default 'Bora <onboarding@resend.dev>';

alter table communities
  add column if not exists email_domain text
  check (email_domain is null or email_domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$');

alter table bookings
  add column if not exists cancelled_by  text check (cancelled_by in ('passenger', 'driver', 'ride')),
  add column if not exists cancel_reason text check (char_length(cancel_reason) <= 200);

-- ---------------------------------------------------------------------
-- Novas tabelas
-- ---------------------------------------------------------------------
create table if not exists ride_messages (
  id         bigint generated always as identity primary key,
  ride_id    uuid not null references rides (id) on delete cascade,
  sender_id  uuid not null default auth.uid() references profiles (id) on delete cascade,
  body       text not null check (char_length(trim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists ride_messages_ride_idx on ride_messages (ride_id, created_at);

create table if not exists verified_emails (
  user_id     uuid not null references profiles (id) on delete cascade,
  email       text not null unique,
  domain      text not null,
  verified_at timestamptz not null default now(),
  primary key (user_id, email)
);

create table if not exists email_codes (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references profiles (id) on delete cascade,
  email      text not null,
  code_hash  text not null,
  attempts   int  not null default 0,
  expires_at timestamptz not null,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists email_codes_user_idx on email_codes (user_id, created_at desc);

-- =====================================================================
-- FUNÇÕES
-- =====================================================================

create or replace function keep_alive() returns text
language sql stable security definer set search_path = public as $$
  select 'ok'::text where exists (select 1 from app_config);
$$;

create or replace function is_ride_participant(p_ride uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rides where id = p_ride and driver_id = p_user)
      or exists (select 1 from bookings where ride_id = p_ride and passenger_id = p_user
                                          and status in ('reserved', 'boarded'));
$$;

create or replace function can_post_in_ride_chat(p_ride uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_ride_participant(p_ride, p_user)
     and exists (select 1 from rides where id = p_ride and status in ('open', 'in_progress'));
$$;

create or replace function ride_chat_participants(p_ride uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_ride_participant(p_ride, auth.uid()) then raise exception 'not_allowed'; end if;
  return (
    select jsonb_agg(x.j order by x.ord)
    from (
      select person_json(r.driver_id) || jsonb_build_object('role', 'driver') as j, 0 as ord
        from rides r where r.id = p_ride
      union all
      select person_json(b.passenger_id) || jsonb_build_object('role', 'passenger'), 1
        from bookings b where b.ride_id = p_ride and b.status in ('reserved', 'boarded')
    ) x);
end $$;

-- Motorista remove um passageiro (ele não consegue reservar de novo)
create or replace function remove_passenger(p_booking uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_ride rides;
begin
  select * into v_b from bookings where id = p_booking for update;
  if v_b.id is null then raise exception 'not_allowed'; end if;
  select * into v_ride from rides where id = v_b.ride_id for update;
  if v_ride.driver_id is distinct from auth.uid() then raise exception 'not_allowed'; end if;
  if v_b.status <> 'reserved' or v_ride.status <> 'open' then raise exception 'cannot_remove_passenger'; end if;

  update bookings
     set status = 'cancelled', cancelled_by = 'driver', cancel_reason = nullif(trim(p_reason), '')
   where id = p_booking;
  update rides set seats_available = seats_available + 1 where id = v_ride.id;
end $$;

create or replace function cancel_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_b bookings;
begin
  select * into v_b from bookings where id = p_booking and passenger_id = auth.uid() for update;
  if v_b.id is null or v_b.status <> 'reserved' then raise exception 'cannot_cancel'; end if;
  update bookings set status = 'cancelled', cancelled_by = 'passenger' where id = p_booking;
  update rides set seats_available = seats_available + 1
   where id = v_b.ride_id and status in ('open', 'in_progress');
end $$;

create or replace function cancel_ride(p_ride uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update rides set status = 'cancelled'
   where id = p_ride and driver_id = auth.uid() and status = 'open';
  if not found then raise exception 'not_allowed'; end if;
  update bookings set status = 'cancelled', cancelled_by = 'ride'
   where ride_id = p_ride and status = 'reserved';
end $$;

create or replace function book_seat(p_ride uuid, p_pickup text, p_dropoff text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; v_ride rides; v_driver_gender gender;
  v_a ride_stops; v_b ride_stops; v_distance int; v_id uuid;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;

  select * into v_ride from rides where id = p_ride for update;
  if v_ride.id is null or v_ride.status <> 'open' then raise exception 'ride_unavailable'; end if;
  if v_ride.driver_id = v_me.id then raise exception 'cannot_book_own_ride'; end if;
  if not can_access_ride(p_ride, v_me.id) then raise exception 'ride_unavailable'; end if;
  if v_ride.seats_available < 1 then raise exception 'ride_full'; end if;
  if v_me.identity_status <> 'approved' then raise exception 'identity_not_verified'; end if;
  if not exists (select 1 from emergency_contacts where user_id = v_me.id)
    then raise exception 'emergency_contact_required'; end if;

  if exists (select 1 from bookings where ride_id = p_ride and passenger_id = v_me.id and cancelled_by = 'driver')
    then raise exception 'removed_by_driver'; end if;

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

-- ---------------------------------------------------------------------
-- Comunidades por e-mail institucional
-- ---------------------------------------------------------------------
create or replace function email_matches_domain(p_email text, p_domain text) returns boolean
language sql immutable as $$
  select split_part(lower(p_email), '@', 2) = p_domain
      or split_part(lower(p_email), '@', 2) like '%.' || p_domain;
$$;

drop function if exists create_community(text, text, community_kind, community_join, text);
create or replace function create_community(
  p_name text, p_description text, p_kind community_kind, p_join_mode community_join,
  p_anchor_stop text, p_email_domain text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_domain text;
begin
  if not exists (select 1 from profiles where id = auth.uid() and identity_status = 'approved')
    then raise exception 'identity_not_verified'; end if;
  if (select count(*) from communities where created_by = auth.uid() and active) >= 3
    then raise exception 'community_limit_reached'; end if;

  v_domain := nullif(lower(trim(both '@ ' from coalesce(p_email_domain, ''))), '');
  if p_join_mode::text = 'email_domain' then
    if v_domain is null or v_domain !~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$' then raise exception 'invalid_email_domain'; end if;
    if v_domain in ('gmail.com', 'hotmail.com', 'outlook.com', 'yahoo.com', 'yahoo.com.br', 'icloud.com', 'live.com', 'bol.com.br', 'uol.com.br')
      then raise exception 'public_email_domain'; end if;
  else
    v_domain := null;
  end if;

  insert into communities (name, description, kind, join_mode, anchor_stop_id, created_by, email_domain)
  values (trim(p_name), coalesce(trim(p_description), ''), p_kind, p_join_mode, p_anchor_stop, auth.uid(), v_domain)
  returning id into v_id;
  insert into community_members (community_id, user_id, role) values (v_id, auth.uid(), 'owner');
  return v_id;
end $$;

create or replace function community_preview(p_invite_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_c communities;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v_c from communities where invite_code = upper(trim(p_invite_code)) and active;
  if v_c.id is null then raise exception 'invalid_invite_code'; end if;
  return jsonb_build_object(
    'id', v_c.id, 'name', v_c.name, 'kind', v_c.kind, 'join_mode', v_c.join_mode,
    'email_domain', v_c.email_domain,
    'already_verified', exists (select 1 from verified_emails
                                 where user_id = auth.uid() and email_matches_domain(email, v_c.email_domain)));
end $$;

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

  if v_c.join_mode::text = 'email_domain'
     and not exists (select 1 from verified_emails
                      where user_id = auth.uid() and email_matches_domain(email, v_c.email_domain))
    then raise exception 'email_verification_required'; end if;

  v_status := case when v_c.join_mode::text = 'approval' then 'pending' else 'active' end;
  insert into community_members (community_id, user_id, status) values (v_c.id, auth.uid(), v_status);
  return v_status;
end $$;

-- Envia o código pelo Resend (chave no Vault como 'resend_api_key'; precisa do pg_net).
-- Sem chave, devolve false e o app usa o código de DEV.
create or replace function send_code_email(p_to text, p_code text, p_community text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_key text; v_from text;
begin
  select email_from into v_from from app_config;
  begin
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  exception when others then v_key := null;
  end;
  if v_key is null then return false; end if;

  begin
    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body    := jsonb_build_object(
        'from', v_from, 'to', jsonb_build_array(p_to),
        'subject', 'Seu código do Bora: ' || p_code,
        'html', format('<p>Use o código <b style="font-size:22px;letter-spacing:4px">%s</b> para entrar na comunidade <b>%s</b> no Bora.</p>'
                       || '<p>Ele vale por 15 minutos. Se não foi você, ignore este e-mail.</p>', p_code, p_community)));
    return true;
  exception when others then
    return false;
  end;
end $$;

create or replace function request_community_email_code(p_invite_code text, p_email text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_c communities; v_email text; v_code text; v_sent boolean; v_echo boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v_c from communities where invite_code = upper(trim(p_invite_code)) and active;
  if v_c.id is null then raise exception 'invalid_invite_code'; end if;
  if v_c.join_mode::text <> 'email_domain' then raise exception 'not_allowed'; end if;

  v_email := lower(trim(p_email));
  if v_email !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' then raise exception 'invalid_email'; end if;
  if not email_matches_domain(v_email, v_c.email_domain) then raise exception 'email_wrong_domain'; end if;
  if exists (select 1 from verified_emails where email = v_email and user_id <> auth.uid())
    then raise exception 'email_in_use'; end if;
  if (select count(*) from email_codes where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 5
    then raise exception 'too_many_codes'; end if;

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  update email_codes set used_at = now() where user_id = auth.uid() and used_at is null;  -- só o último vale
  insert into email_codes (user_id, email, code_hash, expires_at)
  values (auth.uid(), v_email, crypt(v_code, gen_salt('bf')), now() + interval '15 minutes');

  v_sent := send_code_email(v_email, v_code, v_c.name);
  select email_dev_echo into v_echo from app_config;
  if not v_sent and not v_echo then raise exception 'email_not_configured'; end if;

  return jsonb_build_object('sent', v_sent, 'dev_code', case when v_echo then v_code end);
end $$;

create or replace function confirm_community_email(p_invite_code text, p_code text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare v_c communities; v_ec email_codes; v_status member_status;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v_c from communities where invite_code = upper(trim(p_invite_code)) and active;
  if v_c.id is null then raise exception 'invalid_invite_code'; end if;

  select * into v_ec from email_codes
   where user_id = auth.uid() and used_at is null
   order by created_at desc limit 1 for update;
  if v_ec.id is null or v_ec.expires_at < now() then raise exception 'code_expired'; end if;
  if v_ec.attempts >= 5 then raise exception 'too_many_attempts'; end if;

  if v_ec.code_hash <> crypt(trim(p_code), v_ec.code_hash) then
    update email_codes set attempts = attempts + 1 where id = v_ec.id;
    return 'wrong_code';
  end if;
  update email_codes set used_at = now() where id = v_ec.id;

  if not email_matches_domain(v_ec.email, v_c.email_domain) then raise exception 'email_wrong_domain'; end if;
  begin
    insert into verified_emails (user_id, email, domain)
    values (auth.uid(), v_ec.email, split_part(v_ec.email, '@', 2))
    on conflict (user_id, email) do update set verified_at = now();
  exception when unique_violation then
    raise exception 'email_in_use';
  end;

  select status into v_status from community_members where community_id = v_c.id and user_id = auth.uid();
  if v_status = 'banned' then raise exception 'banned_from_community'; end if;
  if v_status is not null then return v_status::text; end if;
  insert into community_members (community_id, user_id, status) values (v_c.id, auth.uid(), 'active');
  return 'active';
end $$;

-- =====================================================================
-- RLS, permissões e Realtime
-- =====================================================================
alter table ride_messages   enable row level security;
alter table verified_emails enable row level security;
alter table email_codes     enable row level security;

drop policy if exists "read ride chat" on ride_messages;
create policy "read ride chat" on ride_messages for select to authenticated
  using (is_ride_participant(ride_id, auth.uid()));
drop policy if exists "write ride chat" on ride_messages;
create policy "write ride chat" on ride_messages for insert to authenticated
  with check (sender_id = auth.uid() and can_post_in_ride_chat(ride_id, auth.uid()));

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;
revoke execute on function send_code_email(text, text, text) from authenticated;  -- só uso interno
grant  execute on function keep_alive() to anon;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and tablename = 'ride_messages') then
    alter publication supabase_realtime add table ride_messages;
  end if;
end $$;
