-- =====================================================================
-- BORA — 0009: dois jeitos de embarcar
--
--  * Perto da saída do motorista (até meet_radius_m, 400 m) e antes de ele
--    sair: o passageiro vai a pé até o carro ("Ir até o carro").
--  * Mais longe: o passageiro vai até uma parada que o carro vai passar e
--    recebe o horário-limite para estar lá ("Ir até a parada").
--
-- O ponto de saída do motorista agora sempre entra na rota. Quando já existe
-- parada perto dele, fica marcado como meet_only (só serve para quem está
-- pertinho, no modo "ir até o carro").
-- Cada reserva passa a ter pickup_mode e pickup_eta (o motorista vê
-- "pegar Fulano na parada X às HH:MM").
-- =====================================================================

alter table stops add column if not exists meet_only boolean not null default false;

alter table app_config
  add column if not exists meet_radius_m  int not null default 400,
  add column if not exists walk_m_per_min int not null default 75,   -- ~4,5 km/h
  add column if not exists pickup_buffer_min int not null default 2; -- chegar um pouco antes

alter table bookings
  add column if not exists pickup_mode text not null default 'stop' check (pickup_mode in ('car', 'stop')),
  add column if not exists pickup_eta  timestamptz;

-- Horário previsto em que o carro passa numa parada da viagem
create or replace function stop_eta(p_ride uuid, p_stop text) returns timestamptz
language sql stable security definer set search_path = public as $$
  select r.departure_at + make_interval(secs => rs.distance_from_start_m / (c.avg_speed_kmh / 3.6))
  from rides r join ride_stops rs on rs.ride_id = r.id and rs.stop_id = p_stop, app_config c
  where r.id = p_ride;
$$;

create or replace function rebuild_ride_stops(p_ride uuid) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_r rides; v_len int; v_snap int; v_walk int; v_count int;
  v_start geography; v_end geography; v_o text; v_d text; v_near_o boolean; v_need_d boolean;
begin
  select * into v_r from rides where id = p_ride;
  if v_r.route is null then return 0; end if;
  select stop_snap_m, walk_radius_m into v_snap, v_walk from app_config;
  v_len := st_length(v_r.route::geography)::int;
  v_start := st_startpoint(v_r.route)::geography;
  v_end := st_endpoint(v_r.route)::geography;
  v_o := 'r_' || replace(p_ride::text, '-', '') || '_o';
  v_d := 'r_' || replace(p_ride::text, '-', '') || '_d';

  delete from ride_stops where ride_id = p_ride;
  delete from stops where ride_id = p_ride
     and not exists (select 1 from bookings b where b.pickup_stop_id = stops.id or b.dropoff_stop_id = stops.id);

  create temp table if not exists _on_route (id text, frac double precision, geog geography) on commit drop;
  delete from _on_route;
  insert into _on_route
  select s.id, st_linelocatepoint(v_r.route, s.geog::geometry), s.geog
    from stops s
   where s.ride_id is null and s.active and s.boardable
     and st_dwithin(s.geog, v_r.route::geography, v_snap);

  v_near_o := exists (select 1 from _on_route where st_dwithin(geog, v_start, v_walk));
  v_need_d := not exists (select 1 from _on_route where st_dwithin(geog, v_end, v_walk));

  -- Saída do motorista: sempre na rota (meet_only quando já há parada perto)
  insert into stops (id, name, region, lat, lng, boardable, active, source, ride_id, meet_only)
  values (v_o, left('Saída · ' || coalesce(v_r.origin_label, 'ponto do motorista'), 80), 'Ponto do motorista',
          st_y(st_startpoint(v_r.route)), st_x(st_startpoint(v_r.route)), true, true, 'ride', p_ride, v_near_o)
  on conflict (id) do update
    set name = excluded.name, lat = excluded.lat, lng = excluded.lng, active = true, meet_only = excluded.meet_only;

  if v_need_d then
    insert into stops (id, name, region, lat, lng, boardable, active, source, ride_id)
    values (v_d, left('Chegada · ' || coalesce(v_r.dest_label, 'ponto do motorista'), 80), 'Ponto do motorista',
            st_y(st_endpoint(v_r.route)), st_x(st_endpoint(v_r.route)), true, true, 'ride', p_ride)
    on conflict (id) do update set name = excluded.name, lat = excluded.lat, lng = excluded.lng, active = true;
  end if;

  insert into ride_stops (ride_id, stop_id, seq, distance_from_start_m)
  select p_ride, x.id, row_number() over (order by x.frac, x.tie), (x.frac * v_len)::int
  from (
    select id, frac, 1 as tie from _on_route
    union all select v_o, 0, 0
    union all select v_d, 1, 2 where v_need_d
  ) x;
  get diagnostics v_count = row_count;

  update rides set path = coalesce((select array_agg(stop_id order by seq) from ride_stops where ride_id = p_ride), '{}')
   where id = p_ride;
  return v_count;
end $$;

-- ---------------------------------------------------------------------
-- Busca com os dois modos
-- ---------------------------------------------------------------------
create or replace function search_rides_near(
  p_from_lat double precision, p_from_lng double precision,
  p_to_lat   double precision, p_to_lng   double precision,
  p_only_my_communities boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me profiles; v_c app_config; v_from geography; v_to geography; v_result jsonb;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;
  select * into v_c from app_config;
  v_from := st_setsrid(st_makepoint(p_from_lng, p_from_lat), 4326)::geography;
  v_to   := st_setsrid(st_makepoint(p_to_lng,   p_to_lat),   4326)::geography;

  select coalesce(jsonb_agg(o.offer order by o.has_shared desc, o.car_first, o.eta, o.walk_total), '[]'::jsonb)
    into v_result
  from (
    select jsonb_build_object(
             'ride', ride_json(r.id),
             'pickup_mode', pu.mode,
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
           cardinality(shared_communities(v_me.id, r.driver_id)) > 0 as has_shared,
           (pu.mode <> 'car') as car_first,
           pu.walk_m + dr.walk_m as walk_total,
           e.eta
    from rides r
    join profiles d on d.id = r.driver_id
    -- Embarque: o carro (se estou pertinho da saída e ele ainda não saiu) ou a parada mais próxima
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, v_from))::int walk_m,
             case when s.ride_id = r.id and rs.seq = 1 and st_dwithin(s.geog, v_from, v_c.meet_radius_m)
                  then 'car' else 'stop' end as mode
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id
        and (
          (not s.meet_only and st_dwithin(s.geog, v_from, v_c.walk_radius_m))
          or (s.ride_id = r.id and rs.seq = 1 and st_dwithin(s.geog, v_from, v_c.meet_radius_m)
              and r.departure_at > now() - interval '2 minutes')
        )
      order by (s.ride_id = r.id and rs.seq = 1 and st_dwithin(s.geog, v_from, v_c.meet_radius_m)) desc,
               st_distance(s.geog, v_from)
      limit 1) pu
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, v_to))::int walk_m
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id and rs.seq > pu.seq and not s.meet_only
        and st_dwithin(s.geog, v_to, v_c.walk_radius_m)
      order by st_distance(s.geog, v_to) limit 1) dr
    cross join lateral (
      select r.departure_at + make_interval(secs => pu.dist / (v_c.avg_speed_kmh / 3.6)) as eta,
             greatest(1, ceil(pu.walk_m::numeric / v_c.walk_m_per_min))::int as walk_min) e
    where r.status = 'open' and r.seats_available > 0
      and e.eta > now()                                   -- o carro ainda não passou por esse ponto
      and r.driver_id <> v_me.id
      and r.route is not null
      and st_dwithin(r.route::geography, v_from, v_c.walk_radius_m)
      and st_dwithin(r.route::geography, v_to,   v_c.walk_radius_m)
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

-- Reserva grava o modo e o horário combinado
create or replace function set_booking_pickup() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_seq int; v_virtual boolean;
begin
  select rs.seq, s.ride_id is not null into v_seq, v_virtual
    from ride_stops rs join stops s on s.id = rs.stop_id
   where rs.ride_id = new.ride_id and rs.stop_id = new.pickup_stop_id;
  new.pickup_mode := case when v_seq = 1 and v_virtual then 'car' else 'stop' end;
  new.pickup_eta := stop_eta(new.ride_id, new.pickup_stop_id);
  return new;
end $$;

drop trigger if exists bookings_pickup on bookings;
create trigger bookings_pickup before insert on bookings
  for each row execute function set_booking_pickup();

update bookings b set pickup_eta = stop_eta(b.ride_id, b.pickup_stop_id)
 where pickup_eta is null and status in ('reserved', 'boarded');

-- Motorista: reservas em ordem de embarque, com nome da parada e horário
create or replace function my_rides() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(
           ride_json(r.id) || jsonb_build_object('bookings', coalesce((
             select jsonb_agg(to_jsonb(b) - 'boarding_code'
                      || jsonb_build_object(
                           'passenger', person_json(b.passenger_id),
                           'pickup_name', (select name from stops where id = b.pickup_stop_id),
                           'shared_communities', to_jsonb(shared_communities(r.driver_id, b.passenger_id)))
                      order by b.pickup_eta nulls last, b.created_at)
             from bookings b where b.ride_id = r.id and b.status <> 'cancelled'), '[]'::jsonb))
           order by r.departure_at), '[]'::jsonb)
  from rides r where r.driver_id = auth.uid();
$$;

-- Mapa geral: pontos de motorista nunca aparecem como parada
revoke execute on function rebuild_ride_stops(uuid), set_booking_pickup() from public, anon, authenticated;
grant execute on function stop_eta(uuid, text) to authenticated;

select rebuild_ride_stops(id) from rides where route is not null and status in ('open', 'in_progress');
