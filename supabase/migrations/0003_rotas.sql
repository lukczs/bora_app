-- =====================================================================
-- BORA — 0003: rotas reais com PostGIS
-- Rode DEPOIS do schema.sql e da 0002, uma vez, no SQL Editor do Supabase.
--
-- Como funciona:
--  * O app do motorista pede a rota à OpenRouteService (origem -> destino)
--    e manda a linha (GeoJSON) para publish_ride_route.
--  * O servidor mede a rota sozinho (não confia na distância do app) e
--    descobre quais paradas ficam a até 150 m do caminho. Elas viram os
--    pontos de embarque/desembarque, na ordem em que o carro passa.
--  * O passageiro busca por ponto de origem e destino (onde ele está e
--    para onde vai). search_rides_near acha viagens que passam perto dos
--    dois pontos, na ordem certa, e indica a parada mais próxima de cada.
--  * book_seat, cancelamentos e o grafo antigo continuam funcionando.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------
-- Ajustes de configuração
-- ---------------------------------------------------------------------
alter table app_config
  add column if not exists stop_snap_m      int not null default 150,   -- parada conta se estiver a até X m da rota
  add column if not exists walk_radius_m    int not null default 800,   -- quanto o passageiro aceita andar até a parada
  add column if not exists max_route_km     int not null default 120;   -- trava contra rotas absurdas

-- ---------------------------------------------------------------------
-- Geometria das paradas (gerada a partir de lat/lng)
-- ---------------------------------------------------------------------
alter table stops
  add column if not exists geog extensions.geography(Point, 4326)
  generated always as (extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography) stored;
create index if not exists stops_geog_idx on stops using gist (geog);

-- ---------------------------------------------------------------------
-- Rota real da viagem
-- ---------------------------------------------------------------------
alter table rides
  add column if not exists route          extensions.geometry(LineString, 4326),
  add column if not exists origin_label   text,
  add column if not exists dest_label     text;
create index if not exists rides_route_idx on rides using gist (route);

-- Busca sem resultado agora pode ser por ponto (não só por parada)
alter table unmet_searches
  alter column pickup  drop not null,
  alter column dropoff drop not null,
  add column if not exists from_geog extensions.geography(Point, 4326),
  add column if not exists to_geog   extensions.geography(Point, 4326);

-- =====================================================================
-- FUNÇÕES
-- =====================================================================

-- Converte o GeoJSON LineString vindo do app e valida o básico
create or replace function parse_route(p_geojson jsonb) returns extensions.geometry
language plpgsql immutable set search_path = public, extensions as $$
declare v_geom geometry;
begin
  if p_geojson is null or p_geojson->>'type' <> 'LineString' then raise exception 'invalid_route'; end if;
  v_geom := st_setsrid(st_geomfromgeojson(p_geojson::text), 4326);
  if st_npoints(v_geom) < 2 or not st_isvalid(v_geom) then raise exception 'invalid_route'; end if;
  -- caixa do DF e Entorno (com folga)
  if not st_within(v_geom, st_makeenvelope(-48.7, -16.5, -47.0, -15.2, 4326)) then
    raise exception 'route_outside_area';
  end if;
  return v_geom;
end $$;

-- Paradas ativas perto de um ponto (para o mapa e para escolher embarque)
create or replace function stops_near(p_lat double precision, p_lng double precision, p_radius_m int default 1000)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'name', s.name, 'region', s.region, 'lat', s.lat, 'lng', s.lng,
           'distance_m', round(st_distance(s.geog, p.g))::int) order by st_distance(s.geog, p.g)), '[]'::jsonb)
  from (select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography g) p
  join stops s on s.active and s.boardable and st_dwithin(s.geog, p.g, least(p_radius_m, 5000));
$$;

-- Recalcula as paradas de uma viagem a partir da rota
create or replace function rebuild_ride_stops(p_ride uuid) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare v_route geometry; v_len int; v_snap int; v_count int;
begin
  select route into v_route from rides where id = p_ride;
  if v_route is null then return 0; end if;
  select stop_snap_m into v_snap from app_config;
  v_len := st_length(v_route::geography)::int;

  delete from ride_stops where ride_id = p_ride;
  insert into ride_stops (ride_id, stop_id, seq, distance_from_start_m)
  select p_ride, x.id, row_number() over (order by x.frac), (x.frac * v_len)::int
  from (
    select s.id, st_linelocatepoint(v_route, s.geog::geometry) as frac
    from stops s
    where s.active and s.boardable and st_dwithin(s.geog, v_route::geography, v_snap)
  ) x;
  get diagnostics v_count = row_count;

  update rides set path = coalesce((select array_agg(stop_id order by seq) from ride_stops where ride_id = p_ride), '{}')
   where id = p_ride;
  return v_count;
end $$;

-- Publica viagem com rota real (substitui publish_ride para quem tem rota)
create or replace function publish_ride_route(
  p_vehicle uuid, p_route jsonb, p_origin_label text, p_dest_label text,
  p_departure timestamptz, p_seats int, p_recurring int[], p_women_only boolean, p_communities uuid[]
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me profiles; v_vehicle vehicles; v_route geometry; v_len int; v_max int;
  v_ride uuid; v_c uuid; v_stops int;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  if v_me.identity_status <> 'approved' then raise exception 'identity_not_verified'; end if;
  if p_women_only and v_me.gender is distinct from 'female' then raise exception 'women_only_not_allowed'; end if;

  select * into v_vehicle from vehicles where id = p_vehicle and owner_id = v_me.id;
  if v_vehicle.id is null then raise exception 'vehicle_not_found'; end if;
  if p_seats < 1 or p_seats > v_vehicle.seats then raise exception 'invalid_seats'; end if;
  if p_departure < now() - interval '5 minutes' then raise exception 'departure_in_past'; end if;

  v_route := parse_route(p_route);
  v_len := st_length(v_route::geography)::int;
  select max_route_km * 1000 into v_max from app_config;
  if v_len < 500 or v_len > v_max then raise exception 'invalid_route_length'; end if;

  if p_communities is not null then
    foreach v_c in array p_communities loop
      if not is_community_member(v_c, v_me.id) then raise exception 'not_a_member'; end if;
    end loop;
  end if;

  insert into rides (driver_id, vehicle_id, path, distance_m, departure_at, recurring_days,
                     seats_total, seats_available, women_only, visibility,
                     route, origin_label, dest_label)
  values (v_me.id, p_vehicle, '{}', v_len, p_departure, coalesce(p_recurring, '{}'),
          p_seats, p_seats, coalesce(p_women_only, false),
          case when coalesce(array_length(p_communities, 1), 0) > 0
               then 'communities'::ride_visibility else 'public'::ride_visibility end,
          v_route, nullif(trim(p_origin_label), ''), nullif(trim(p_dest_label), ''))
  returning id into v_ride;

  if p_communities is not null then
    insert into ride_communities (ride_id, community_id) select v_ride, unnest(p_communities);
  end if;

  v_stops := rebuild_ride_stops(v_ride);
  if v_stops < 2 then raise exception 'route_without_stops'; end if;  -- desfaz tudo (rollback)

  return jsonb_build_object('ride_id', v_ride, 'distance_m', v_len, 'stops', v_stops);
end $$;

-- Rota em GeoJSON para o app desenhar (só quem pode ver a viagem)
create or replace function ride_route(p_ride uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select st_asgeojson(r.route)::jsonb from rides r
  where r.id = p_ride and can_access_ride(r.id, auth.uid());
$$;

-- Busca por ponto de origem/destino do passageiro
create or replace function search_rides_near(
  p_from_lat double precision, p_from_lng double precision,
  p_to_lat   double precision, p_to_lng   double precision,
  p_only_my_communities boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me profiles; v_walk int; v_from geography; v_to geography; v_result jsonb;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  select walk_radius_m into v_walk from app_config;
  v_from := st_setsrid(st_makepoint(p_from_lng, p_from_lat), 4326)::geography;
  v_to   := st_setsrid(st_makepoint(p_to_lng,   p_to_lat),   4326)::geography;

  select coalesce(jsonb_agg(o.offer order by o.has_shared desc, o.walk_total, o.departure_at), '[]'::jsonb)
    into v_result
  from (
    select jsonb_build_object(
             'ride', ride_json(r.id),
             'pickup',  jsonb_build_object('id', pu.id, 'name', pu.name, 'lat', pu.lat, 'lng', pu.lng, 'walk_m', pu.walk_m),
             'dropoff', jsonb_build_object('id', dr.id, 'name', dr.name, 'lat', dr.lat, 'lng', dr.lng, 'walk_m', dr.walk_m),
             'pickup_stop_id', pu.id, 'dropoff_stop_id', dr.id,
             'distance_m', dr.dist - pu.dist,
             'price_cents', compute_price(dr.dist - pu.dist),
             'shared_communities', to_jsonb(shared_communities(v_me.id, r.driver_id))) as offer,
           cardinality(shared_communities(v_me.id, r.driver_id)) > 0 as has_shared,
           pu.walk_m + dr.walk_m as walk_total,
           r.departure_at
    from rides r
    join profiles d on d.id = r.driver_id
    -- parada da rota mais perto de onde o passageiro está
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, v_from))::int walk_m
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id and st_dwithin(s.geog, v_from, v_walk)
      order by st_distance(s.geog, v_from) limit 1) pu
    -- parada da rota mais perto do destino, depois do embarque
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, v_to))::int walk_m
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id and rs.seq > pu.seq and st_dwithin(s.geog, v_to, v_walk)
      order by st_distance(s.geog, v_to) limit 1) dr
    where r.status = 'open' and r.seats_available > 0
      and r.departure_at > now() - interval '1 hour'
      and r.driver_id <> v_me.id
      and r.route is not null
      and st_dwithin(r.route::geography, v_from, v_walk)       -- filtro rápido pelo índice
      and st_dwithin(r.route::geography, v_to,   v_walk)
      and can_access_ride(r.id, v_me.id)
      and (not r.women_only        or v_me.gender = 'female')
      and (not v_me.women_only_pref or d.gender = 'female')
      and (not p_only_my_communities or cardinality(shared_communities(v_me.id, r.driver_id)) > 0)
  ) o;

  if v_result = '[]'::jsonb then
    insert into unmet_searches (user_id, from_geog, to_geog) values (v_me.id, v_from, v_to);
  end if;
  return v_result;
end $$;

-- Demanda não atendida perto de uma rota (para mostrar ao motorista)
create or replace function demand_near_route(p_route jsonb) returns int
language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from unmet_searches u, app_config c
  where u.created_at > now() - interval '14 days'
    and u.from_geog is not null
    and st_dwithin(u.from_geog, parse_route(p_route)::geography, c.walk_radius_m)
    and st_dwithin(u.to_geog,   parse_route(p_route)::geography, c.walk_radius_m);
$$;

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
revoke execute on function parse_route(jsonb), rebuild_ride_stops(uuid),
                           stops_near(double precision, double precision, int),
                           publish_ride_route(uuid, jsonb, text, text, timestamptz, int, int[], boolean, uuid[]),
                           ride_route(uuid),
                           search_rides_near(double precision, double precision, double precision, double precision, boolean),
                           demand_near_route(jsonb)
       from public, anon, authenticated;
grant  execute on function stops_near(double precision, double precision, int),
                           publish_ride_route(uuid, jsonb, text, text, timestamptz, int, int[], boolean, uuid[]),
                           ride_route(uuid),
                           search_rides_near(double precision, double precision, double precision, double precision, boolean),
                           demand_near_route(jsonb)
       to authenticated;
