-- =====================================================================
-- BORA — 0010: eventos
--
-- Qualquer usuário verificado cria um evento (jogo, show, festa, semana
-- acadêmica). As caronas se organizam em volta dele:
--  * IDA: rotas que terminam no evento e passam a até 5 km de você.
--  * VOLTA: rotas que saem do evento e passam a até 5 km de você.
-- Como o evento é marcado com antecedência, o passageiro pode ir até um
-- ponto mais longe do que no dia a dia e reservar a vaga dias antes.
--
-- Travas: só verificado cria, no máximo 5 eventos futuros por pessoa,
-- aviso de evento parecido (300 m, mesmo dia) e o evento some 1 dia depois.
-- =====================================================================

create table if not exists events (
  id              uuid primary key default gen_random_uuid(),
  name            text not null check (char_length(trim(name)) between 3 and 80),
  kind            text not null default 'outro' check (kind in ('esporte', 'show', 'festa', 'faculdade', 'outro')),
  description     text not null default '' check (char_length(description) <= 500),
  venue_label     text not null check (char_length(venue_label) between 2 and 120),
  meeting_point   text check (char_length(meeting_point) <= 120),
  lat             double precision not null,
  lng             double precision not null,
  geog            extensions.geography(Point, 4326)
                  generated always as (extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography) stored,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  community_id    uuid references communities (id) on delete cascade,   -- null = público
  invite_code     text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  created_by      uuid not null references profiles (id) on delete cascade,
  status          text not null default 'active' check (status in ('active', 'cancelled')),
  created_at      timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists events_geog_idx on events using gist (geog);
create index if not exists events_time_idx on events (starts_at) where status = 'active';
alter table events enable row level security;

alter table rides
  add column if not exists event_id  uuid references events (id) on delete set null,
  add column if not exists event_leg text check (event_leg in ('ida', 'volta'));
create index if not exists rides_event_idx on rides (event_id) where event_id is not null;

create table if not exists event_interests (
  event_id   uuid not null references events (id) on delete cascade,
  user_id    uuid not null references profiles (id) on delete cascade,
  leg        text not null check (leg in ('ida', 'volta')),
  lat        double precision not null,
  lng        double precision not null,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id, leg)
);
alter table event_interests enable row level security;

alter table app_config
  add column if not exists event_radius_m     int not null default 5000,  -- caronas a até 5 km de você
  add column if not exists event_venue_m      int not null default 1500,  -- rota precisa chegar/sair a até 1,5 km do local
  add column if not exists event_max_per_user int not null default 5;

-- ---------------------------------------------------------------------
create or replace function can_see_event(p_event uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from events e where e.id = p_event
                  and (e.community_id is null or e.created_by = p_user or is_community_member(e.community_id, p_user)));
$$;

create or replace function event_json(p_event uuid, p_lat double precision default null, p_lng double precision default null)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select to_jsonb(e) - 'geog' - 'created_by'
      || jsonb_build_object(
           'is_mine', e.created_by = auth.uid(),
           'community_name', (select name from communities c where c.id = e.community_id),
           'distance_m', case when p_lat is null then null
                              else round(st_distance(e.geog, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography))::int end,
           'rides_ida',   (select count(*) from rides r where r.event_id = e.id and r.event_leg = 'ida'   and r.status = 'open'),
           'rides_volta', (select count(*) from rides r where r.event_id = e.id and r.event_leg = 'volta' and r.status = 'open'),
           'seats',       (select coalesce(sum(seats_available), 0) from rides r where r.event_id = e.id and r.status = 'open'),
           'interested',  (select count(distinct user_id) from event_interests i where i.event_id = e.id),
           'my_interest', (select coalesce(jsonb_agg(leg), '[]'::jsonb) from event_interests i
                            where i.event_id = e.id and i.user_id = auth.uid()))
  from events e where e.id = p_event;
$$;

-- Eventos que estão por vir (ou acontecendo), mais próximos e mais cedo primeiro
create or replace function upcoming_events(p_lat double precision, p_lng double precision)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(event_json(e.id, p_lat, p_lng) order by e.starts_at), '[]'::jsonb)
  from events e
  where e.status = 'active'
    and e.ends_at > now() - interval '1 day'
    and e.starts_at < now() + interval '60 days'
    and can_see_event(e.id, auth.uid());
$$;

-- Eventos parecidos (mesmo lugar, mesmo dia) para evitar duplicados
create or replace function similar_events(p_lat double precision, p_lng double precision, p_starts_at timestamptz)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(event_json(e.id) order by e.starts_at), '[]'::jsonb)
  from events e
  where e.status = 'active'
    and st_dwithin(e.geog, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, 300)
    and (e.starts_at at time zone 'America/Sao_Paulo')::date = (p_starts_at at time zone 'America/Sao_Paulo')::date
    and can_see_event(e.id, auth.uid());
$$;

create or replace function create_event(
  p_name text, p_kind text, p_venue_label text, p_lat double precision, p_lng double precision,
  p_starts_at timestamptz, p_ends_at timestamptz, p_meeting_point text, p_description text, p_community uuid
) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_me profiles; v_id uuid; v_max int;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  if v_me.identity_status <> 'approved' then raise exception 'identity_not_verified'; end if;
  select event_max_per_user into v_max from app_config;
  if (select count(*) from events where created_by = v_me.id and status = 'active' and ends_at > now()) >= v_max
    then raise exception 'event_limit_reached'; end if;
  if p_starts_at < now() - interval '1 hour' then raise exception 'event_in_past'; end if;
  if p_ends_at <= p_starts_at then raise exception 'event_end_before_start'; end if;
  if p_ends_at > p_starts_at + interval '3 days' then raise exception 'event_too_long'; end if;
  if not st_within(st_setsrid(st_makepoint(p_lng, p_lat), 4326), st_makeenvelope(-48.7, -16.5, -47.0, -15.2, 4326))
    then raise exception 'route_outside_area'; end if;
  if p_community is not null and not is_community_member(p_community, v_me.id) then raise exception 'not_a_member'; end if;

  insert into events (name, kind, venue_label, lat, lng, starts_at, ends_at, meeting_point, description, community_id, created_by)
  values (trim(p_name), coalesce(nullif(p_kind, ''), 'outro'), trim(p_venue_label), p_lat, p_lng, p_starts_at, p_ends_at,
          nullif(trim(coalesce(p_meeting_point, '')), ''), coalesce(trim(p_description), ''), p_community, v_me.id)
  returning id into v_id;
  return v_id;
end $$;

create or replace function cancel_event(p_event uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update events set status = 'cancelled' where id = p_event and created_by = auth.uid();
  if not found then raise exception 'not_allowed'; end if;
end $$;

create or replace function event_by_code(p_code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select event_json(id) from events where invite_code = upper(trim(p_code)) and status = 'active';
$$;

-- "Preciso de carona" (ida e/ou volta), com o ponto de onde a pessoa sai/para onde volta
create or replace function set_event_interest(p_event uuid, p_leg text, p_lat double precision, p_lng double precision, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_see_event(p_event, auth.uid()) then raise exception 'not_allowed'; end if;
  if p_on then
    insert into event_interests (event_id, user_id, leg, lat, lng) values (p_event, auth.uid(), p_leg, p_lat, p_lng)
    on conflict (event_id, user_id, leg) do update set lat = excluded.lat, lng = excluded.lng, created_at = now();
  else
    delete from event_interests where event_id = p_event and user_id = auth.uid() and leg = p_leg;
  end if;
end $$;

-- Motorista publica carona para o evento (mesma validação de rota de sempre)
create or replace function publish_event_ride(
  p_event uuid, p_leg text, p_vehicle uuid, p_route jsonb, p_origin_label text, p_dest_label text,
  p_departure timestamptz, p_seats int, p_women_only boolean
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_e events; v_route geometry; v_res jsonb; v_venue int;
begin
  select * into v_e from events where id = p_event and status = 'active';
  if v_e.id is null or not can_see_event(p_event, auth.uid()) then raise exception 'event_not_found'; end if;
  if p_leg not in ('ida', 'volta') then raise exception 'invalid_route'; end if;
  select event_venue_m into v_venue from app_config;
  v_route := parse_route(p_route);
  if p_leg = 'ida' and not st_dwithin(st_endpoint(v_route)::geography, v_e.geog, v_venue) then raise exception 'route_not_to_event'; end if;
  if p_leg = 'volta' and not st_dwithin(st_startpoint(v_route)::geography, v_e.geog, v_venue) then raise exception 'route_not_from_event'; end if;

  v_res := publish_ride_route(p_vehicle, p_route, p_origin_label, p_dest_label, p_departure, p_seats, null,
                              p_women_only, case when v_e.community_id is null then null else array[v_e.community_id] end);
  update rides set event_id = p_event, event_leg = p_leg where id = (v_res->>'ride_id')::uuid;
  return v_res;
end $$;

-- Caronas do evento perto de você (raio de 5 km, configurável)
create or replace function event_rides(p_event uuid, p_leg text, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_me profiles; v_c app_config; v_me_pt geography; v_e events; v_result jsonb;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  select * into v_e from events where id = p_event;
  if v_e.id is null or not can_see_event(p_event, v_me.id) then raise exception 'event_not_found'; end if;
  select * into v_c from app_config;
  v_me_pt := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  select coalesce(jsonb_agg(o.offer order by o.walk_m, o.eta), '[]'::jsonb) into v_result
  from (
    select jsonb_build_object(
             'ride', ride_json(r.id),
             'leg', p_leg,
             'pickup_mode', case when p_leg = 'ida' and pu.seq = 1 and pu.virtual and pu.walk_m <= v_c.meet_radius_m then 'car' else 'stop' end,
             'pickup',  jsonb_build_object('id', pu.id, 'name', pu.name, 'lat', pu.lat, 'lng', pu.lng, 'walk_m', pu.walk_m),
             'dropoff', jsonb_build_object('id', dr.id, 'name', dr.name, 'lat', dr.lat, 'lng', dr.lng, 'walk_m', dr.walk_m),
             'pickup_stop_id', pu.id, 'dropoff_stop_id', dr.id,
             'distance_m', dr.dist - pu.dist,
             'price_cents', compute_price(dr.dist - pu.dist),
             'pickup_eta', e.eta,
             'walk_min', e.walk_min,
             'be_there_by', e.eta - make_interval(mins => v_c.pickup_buffer_min),
             'leave_by', e.eta - make_interval(mins => v_c.pickup_buffer_min + e.walk_min),
             'dropoff_eta', e.eta + make_interval(secs => (dr.dist - pu.dist) / (v_c.avg_speed_kmh / 3.6)),
             'shared_communities', to_jsonb(shared_communities(v_me.id, r.driver_id))) as offer,
           case when p_leg = 'ida' then pu.walk_m else dr.walk_m end as walk_m,
           e.eta
    from rides r
    join profiles d on d.id = r.driver_id
    -- IDA: embarque = ponto da rota mais perto de você; desembarque = último ponto (o evento)
    -- VOLTA: embarque = primeiro ponto (o evento); desembarque = ponto da rota mais perto de você
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist, s.ride_id is not null as virtual,
             round(st_distance(s.geog, case when p_leg = 'ida' then v_me_pt else v_e.geog end))::int walk_m
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id
        and (p_leg = 'volta' and rs.seq = 1
             or p_leg = 'ida' and st_dwithin(s.geog, v_me_pt, v_c.event_radius_m)
                 and rs.seq < (select max(seq) from ride_stops x where x.ride_id = r.id))
      order by case when p_leg = 'ida' then st_distance(s.geog, v_me_pt) else 0 end
      limit 1) pu
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, case when p_leg = 'volta' then v_me_pt else v_e.geog end))::int walk_m
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id and rs.seq > pu.seq and not s.meet_only
        and (p_leg = 'ida' and rs.seq = (select max(seq) from ride_stops x where x.ride_id = r.id)
             or p_leg = 'volta' and st_dwithin(s.geog, v_me_pt, v_c.event_radius_m))
      order by case when p_leg = 'volta' then st_distance(s.geog, v_me_pt) else 0 end
      limit 1) dr
    cross join lateral (
      select r.departure_at + make_interval(secs => pu.dist / (v_c.avg_speed_kmh / 3.6)) as eta,
             greatest(1, ceil(case when p_leg = 'ida' then pu.walk_m else dr.walk_m end::numeric / v_c.walk_m_per_min))::int as walk_min) e
    where r.event_id = p_event and r.event_leg = p_leg
      and r.status = 'open' and r.seats_available > 0
      and e.eta > now()
      and r.driver_id <> v_me.id
      and can_access_ride(r.id, v_me.id)
      and (not r.women_only        or v_me.gender = 'female')
      and (not v_me.women_only_pref or d.gender = 'female')
  ) o;
  return v_result;
end $$;

-- Procura por carona perto de uma rota (para o motorista ver antes de publicar)
create or replace function event_demand(p_event uuid, p_leg text, p_route jsonb) returns int
language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from event_interests i, app_config c
  where i.event_id = p_event and i.leg = p_leg
    and st_dwithin(st_setsrid(st_makepoint(i.lng, i.lat), 4326)::geography, parse_route(p_route)::geography, c.event_radius_m);
$$;

revoke execute on function can_see_event(uuid, uuid) from public, anon, authenticated;
revoke execute on function event_json(uuid, double precision, double precision), upcoming_events(double precision, double precision),
                           similar_events(double precision, double precision, timestamptz),
                           create_event(text, text, text, double precision, double precision, timestamptz, timestamptz, text, text, uuid),
                           cancel_event(uuid), event_by_code(text),
                           set_event_interest(uuid, text, double precision, double precision, boolean),
                           publish_event_ride(uuid, text, uuid, jsonb, text, text, timestamptz, int, boolean),
                           event_rides(uuid, text, double precision, double precision), event_demand(uuid, text, jsonb)
       from public, anon;
grant execute on function event_json(uuid, double precision, double precision), upcoming_events(double precision, double precision),
                          similar_events(double precision, double precision, timestamptz),
                          create_event(text, text, text, double precision, double precision, timestamptz, timestamptz, text, text, uuid),
                          cancel_event(uuid), event_by_code(text),
                          set_event_interest(uuid, text, double precision, double precision, boolean),
                          publish_event_ride(uuid, text, uuid, jsonb, text, text, timestamptz, int, boolean),
                          event_rides(uuid, text, double precision, double precision), event_demand(uuid, text, jsonb)
      to authenticated;
