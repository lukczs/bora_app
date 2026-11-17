-- =====================================================================
-- BORA — 0005: motoristas por perto (com privacidade) e tempo de chegada
--
-- Privacidade primeiro (lição do DiDi Hitch):
--  * Só aparece no mapa quem tem viagem aberta saindo em até 90 min
--    ou em andamento. Sem viagem, a posição nem é gravada.
--  * Para quem só está olhando o mapa, a posição é arredondada (~150 m)
--    e não vem nome, foto nem placa. Só "um carro com X vagas".
--  * A posição exata só vai para quem tem reserva naquela viagem.
--  * Posição com mais de 2 min é ignorada; com mais de 1 dia é apagada.
-- =====================================================================

create table if not exists driver_presence (
  user_id    uuid primary key references profiles (id) on delete cascade,
  lat        double precision not null,
  lng        double precision not null,
  heading    real,
  updated_at timestamptz not null default now()
);
alter table driver_presence enable row level security;   -- sem policies: só pelas funções

alter table app_config
  add column if not exists avg_speed_kmh     int not null default 30,   -- velocidade média urbana para ETA
  add column if not exists presence_fresh_s  int not null default 120;

-- Viagem "ativa" do motorista agora (aberta saindo logo, ou em andamento)
create or replace function active_ride_of(p_driver uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select id from rides
   where driver_id = p_driver
     and (status = 'in_progress'
          or (status = 'open' and departure_at between now() - interval '30 minutes' and now() + interval '90 minutes'))
   order by (status = 'in_progress') desc, departure_at
   limit 1;
$$;

-- O app do motorista chama a cada ~10 s enquanto tem viagem ativa
create or replace function update_my_location(p_lat double precision, p_lng double precision, p_heading real default null)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if active_ride_of(auth.uid()) is null then
    delete from driver_presence where user_id = auth.uid();
    return false;                                     -- sem viagem ativa: não guarda nada
  end if;
  insert into driver_presence (user_id, lat, lng, heading, updated_at)
  values (auth.uid(), p_lat, p_lng, p_heading, now())
  on conflict (user_id) do update
    set lat = excluded.lat, lng = excluded.lng, heading = excluded.heading, updated_at = now();
  delete from driver_presence where updated_at < now() - interval '1 day';
  return true;
end $$;

create or replace function stop_sharing_location() returns void
language sql security definer set search_path = public as $$
  delete from driver_presence where user_id = auth.uid();
$$;

-- Carros por perto para o mapa (anônimos e arredondados)
create or replace function nearby_drivers(p_lat double precision, p_lng double precision, p_radius_m int default 3000)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_me profiles; v_fresh int; v_result jsonb;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  select presence_fresh_s into v_fresh from app_config;

  select coalesce(jsonb_agg(jsonb_build_object(
           'ride_id', x.ride_id,
           'lat', case when x.mine then x.lat else round(x.lat::numeric, 3)::float end,
           'lng', case when x.mine then x.lng else round(x.lng::numeric, 3)::float end,
           'heading', case when x.mine then x.heading end,
           'seats_available', x.seats_available,
           'is_my_ride', x.mine)), '[]'::jsonb)
    into v_result
  from (
    select r.id ride_id, p.lat, p.lng, p.heading, r.seats_available,
           exists (select 1 from bookings b where b.ride_id = r.id and b.passenger_id = v_me.id
                                              and b.status in ('reserved', 'boarded')) as mine
    from driver_presence p
    join rides r on r.id = active_ride_of(p.user_id)
    join profiles d on d.id = r.driver_id
    where p.updated_at > now() - make_interval(secs => v_fresh)
      and p.user_id <> v_me.id
      and st_dwithin(st_setsrid(st_makepoint(p.lng, p.lat), 4326)::geography,
                     st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, least(p_radius_m, 10000))
      and can_access_ride(r.id, v_me.id)
      and (not r.women_only        or v_me.gender = 'female')
      and (not v_me.women_only_pref or d.gender = 'female')
    limit 60
  ) x;
  return v_result;
end $$;

-- Acompanhar a viagem reservada: posição exata do motorista + ETA até o embarque
create or replace function track_ride(p_ride uuid) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_ride rides; v_p driver_presence; v_b bookings; v_speed int; v_fresh int;
        v_left_m int; v_eta timestamptz; v_live boolean;
begin
  if not is_ride_participant(p_ride, auth.uid()) then raise exception 'not_allowed'; end if;
  select * into v_ride from rides where id = p_ride;
  select * into v_p from driver_presence where user_id = v_ride.driver_id;
  select * into v_b from bookings where ride_id = p_ride and passenger_id = auth.uid()
                                    and status in ('reserved', 'boarded') limit 1;
  select avg_speed_kmh, presence_fresh_s into v_speed, v_fresh from app_config;
  v_live := v_p.user_id is not null and v_p.updated_at > now() - make_interval(secs => v_fresh);

  if v_b.id is not null then
    if v_live and v_ride.route is not null then
      -- quanto falta, pela rota, da posição atual do carro até a parada de embarque
      select greatest(0, (rs.distance_from_start_m
               - st_linelocatepoint(v_ride.route, st_setsrid(st_makepoint(v_p.lng, v_p.lat), 4326))
                 * st_length(v_ride.route::geography)))::int
        into v_left_m
        from ride_stops rs where rs.ride_id = p_ride and rs.stop_id = v_b.pickup_stop_id;
      v_eta := now() + make_interval(secs => v_left_m / (v_speed / 3.6));
    else
      select greatest(v_ride.departure_at, now())
             + make_interval(secs => rs.distance_from_start_m / (v_speed / 3.6))
        into v_eta
        from ride_stops rs where rs.ride_id = p_ride and rs.stop_id = v_b.pickup_stop_id;
    end if;
  end if;

  return jsonb_build_object(
    'ride_id', p_ride, 'status', v_ride.status, 'live', v_live,
    'lat', case when v_live then v_p.lat end, 'lng', case when v_live then v_p.lng end,
    'heading', case when v_live then v_p.heading end,
    'updated_at', v_p.updated_at,
    'pickup_eta', v_eta, 'meters_to_pickup', v_left_m);
end $$;

-- ---------------------------------------------------------------------
-- Busca: agora com ETA no embarque e ordem "mais perto e mais cedo"
-- ---------------------------------------------------------------------
create or replace function search_rides_near(
  p_from_lat double precision, p_from_lng double precision,
  p_to_lat   double precision, p_to_lng   double precision,
  p_only_my_communities boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me profiles; v_walk int; v_speed int; v_from geography; v_to geography; v_result jsonb;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  select walk_radius_m, avg_speed_kmh into v_walk, v_speed from app_config;
  v_from := st_setsrid(st_makepoint(p_from_lng, p_from_lat), 4326)::geography;
  v_to   := st_setsrid(st_makepoint(p_to_lng,   p_to_lat),   4326)::geography;

  select coalesce(jsonb_agg(o.offer order by o.has_shared desc, o.eta, o.walk_total), '[]'::jsonb)
    into v_result
  from (
    select jsonb_build_object(
             'ride', ride_json(r.id),
             'pickup',  jsonb_build_object('id', pu.id, 'name', pu.name, 'lat', pu.lat, 'lng', pu.lng, 'walk_m', pu.walk_m),
             'dropoff', jsonb_build_object('id', dr.id, 'name', dr.name, 'lat', dr.lat, 'lng', dr.lng, 'walk_m', dr.walk_m),
             'pickup_stop_id', pu.id, 'dropoff_stop_id', dr.id,
             'distance_m', dr.dist - pu.dist,
             'price_cents', compute_price(dr.dist - pu.dist),
             'pickup_eta', e.eta,
             'dropoff_eta', e.eta + make_interval(secs => (dr.dist - pu.dist) / (v_speed / 3.6)),
             'shared_communities', to_jsonb(shared_communities(v_me.id, r.driver_id))) as offer,
           cardinality(shared_communities(v_me.id, r.driver_id)) > 0 as has_shared,
           pu.walk_m + dr.walk_m as walk_total,
           e.eta
    from rides r
    join profiles d on d.id = r.driver_id
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, v_from))::int walk_m
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id and st_dwithin(s.geog, v_from, v_walk)
      order by st_distance(s.geog, v_from) limit 1) pu
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, v_to))::int walk_m
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id and rs.seq > pu.seq and st_dwithin(s.geog, v_to, v_walk)
      order by st_distance(s.geog, v_to) limit 1) dr
    cross join lateral (
      select greatest(r.departure_at, now()) + make_interval(secs => pu.dist / (v_speed / 3.6)) as eta) e
    where r.status = 'open' and r.seats_available > 0
      and r.departure_at > now() - interval '1 hour'
      and r.driver_id <> v_me.id
      and r.route is not null
      and st_dwithin(r.route::geography, v_from, v_walk)
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

-- Paradas pelo id (o app busca só as que precisa mostrar)
create or replace function stops_by_ids(p_ids text[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'region', region, 'lat', lat, 'lng', lng,
                                               'boardable', boardable, 'has_shelter', has_shelter, 'is_lit', is_lit)),
                  '[]'::jsonb)
  from stops where id = any (p_ids);
$$;

-- Paradas dentro do retângulo visível do mapa (o app só chama com zoom alto)
create or replace function stops_in_view(p_south double precision, p_west double precision,
                                         p_north double precision, p_east double precision)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'region', s.region,
                                               'lat', s.lat, 'lng', s.lng, 'boardable', s.boardable,
                                               'has_shelter', s.has_shelter, 'is_lit', s.is_lit)), '[]'::jsonb)
  from (select * from stops
         where active and boardable
           and lat between p_south and p_north and lng between p_west and p_east
         limit 300) s;
$$;

-- Rides: devolve também os rótulos de origem/destino da rota real
create or replace function ride_json(p_ride uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select (to_jsonb(r) - 'route')
      || jsonb_build_object(
           'driver',  person_json(r.driver_id),
           'vehicle', vehicle_json(r.vehicle_id),
           'communities', coalesce((
              select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
              from ride_communities rc join communities c on c.id = rc.community_id
              where rc.ride_id = r.id), '[]'::jsonb))
  from rides r where r.id = p_ride;
$$;

revoke execute on function active_ride_of(uuid) from public, anon, authenticated;
revoke execute on function update_my_location(double precision, double precision, real),
                           stop_sharing_location(),
                           nearby_drivers(double precision, double precision, int),
                           track_ride(uuid),
                           stops_by_ids(text[]),
                           stops_in_view(double precision, double precision, double precision, double precision)
       from public, anon;
grant execute on function update_my_location(double precision, double precision, real),
                          stop_sharing_location(),
                          nearby_drivers(double precision, double precision, int),
                          track_ride(uuid),
                          stops_by_ids(text[]),
                          stops_in_view(double precision, double precision, double precision, double precision)
      to authenticated;
