-- =====================================================================
-- BORA — 0012: a corrida
--
--  * Motorista inicia a corrida (start_ride) e o app vira navegação.
--  * Em cada parada: "Embarcou" (board_passenger) ou "Não apareceu"
--    (passenger_no_show); no destino do passageiro: drop_passenger.
--  * finish_ride encerra tudo.
--  * driver_navigation devolve as paradas que ainda têm alguém para pegar
--    ou deixar, em ordem, e uma "versão": quando muda (entrou passageiro,
--    alguém cancelou ou embarcou) o app recalcula a rota.
--  * Com a corrida andando, ainda dá para reservar: só em paradas que o
--    carro ainda não passou (pelo menos ahead_min_m à frente dele).
-- =====================================================================

alter table rides
  add column if not exists started_at  timestamptz,
  add column if not exists finished_at timestamptz;

alter table bookings
  add column if not exists boarded_at timestamptz,
  add column if not exists dropped_at timestamptz;

alter table app_config
  add column if not exists ahead_min_m int not null default 500;  -- parada precisa estar pelo menos isso à frente do carro

-- Quantos metros da rota o carro já andou (0 se não começou).
-- Usa a posição ao vivo; sem GPS recente, estima pelo tempo desde a largada.
create or replace function ride_progress_m(p_ride uuid) returns int
language sql stable security definer set search_path = public, extensions as $$
  select case
    when r.status <> 'in_progress' or r.route is null then 0
    when p.user_id is not null and p.updated_at > now() - make_interval(secs => c.presence_fresh_s)
      then (st_linelocatepoint(r.route, st_setsrid(st_makepoint(p.lng, p.lat), 4326))
            * st_length(r.route::geography))::int
    else least(st_length(r.route::geography),
               extract(epoch from now() - coalesce(r.started_at, r.departure_at)) * c.avg_speed_kmh / 3.6)::int
  end
  from rides r cross join app_config c
  left join driver_presence p on p.user_id = r.driver_id
  where r.id = p_ride;
$$;

-- Horário previsto em que o carro passa numa parada (ao vivo depois que a corrida começa)
create or replace function stop_eta(p_ride uuid, p_stop text) returns timestamptz
language sql stable security definer set search_path = public as $$
  select case
    when r.status = 'in_progress' then
      now() + make_interval(secs => greatest(0, rs.distance_from_start_m - ride_progress_m(r.id)) / (c.avg_speed_kmh / 3.6))
    else r.departure_at + make_interval(secs => rs.distance_from_start_m / (c.avg_speed_kmh / 3.6))
  end
  from rides r join ride_stops rs on rs.ride_id = r.id and rs.stop_id = p_stop, app_config c
  where r.id = p_ride;
$$;

-- ---------------------------------------------------------------------
-- Ciclo da corrida
-- ---------------------------------------------------------------------
create or replace function start_ride(p_ride uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_r rides;
begin
  select * into v_r from rides where id = p_ride and driver_id = auth.uid() for update;
  if v_r.id is null then raise exception 'not_allowed'; end if;
  if v_r.status = 'in_progress' then return ride_json(p_ride); end if;   -- já começou: só reabre
  if v_r.status <> 'open' then raise exception 'ride_unavailable'; end if;
  if v_r.departure_at > now() + interval '60 minutes' then raise exception 'too_early_to_start'; end if;
  if exists (select 1 from rides where driver_id = auth.uid() and status = 'in_progress' and id <> p_ride)
    then raise exception 'ride_already_in_progress'; end if;

  update rides set status = 'in_progress', started_at = now() where id = p_ride;
  update bookings set pickup_eta = stop_eta(p_ride, pickup_stop_id)
   where ride_id = p_ride and status = 'reserved';
  return ride_json(p_ride);
end $$;

create or replace function board_passenger(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_b bookings;
begin
  select b.* into v_b from bookings b join rides r on r.id = b.ride_id
   where b.id = p_booking and r.driver_id = auth.uid() and r.status = 'in_progress' for update of b;
  if v_b.id is null then raise exception 'not_allowed'; end if;
  if v_b.status = 'boarded' then return; end if;
  if v_b.status <> 'reserved' then raise exception 'booking_not_active'; end if;
  update bookings set status = 'boarded', boarded_at = now() where id = p_booking;
end $$;

create or replace function passenger_no_show(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_b bookings;
begin
  select b.* into v_b from bookings b join rides r on r.id = b.ride_id
   where b.id = p_booking and r.driver_id = auth.uid() and r.status = 'in_progress' for update of b;
  if v_b.id is null then raise exception 'not_allowed'; end if;
  if v_b.status <> 'reserved' then raise exception 'booking_not_active'; end if;
  update bookings set status = 'cancelled', cancelled_by = 'no_show', cancel_reason = 'Não apareceu na parada'
   where id = p_booking;
  update rides set seats_available = seats_available + 1 where id = v_b.ride_id;
end $$;

create or replace function drop_passenger(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_b bookings;
begin
  select b.* into v_b from bookings b join rides r on r.id = b.ride_id
   where b.id = p_booking and r.driver_id = auth.uid() and r.status = 'in_progress' for update of b;
  if v_b.id is null then raise exception 'not_allowed'; end if;
  if v_b.status = 'completed' then return; end if;
  if v_b.status <> 'boarded' then raise exception 'booking_not_active'; end if;
  update bookings set status = 'completed', dropped_at = now() where id = p_booking;
  update rides set seats_available = seats_available + 1 where id = v_b.ride_id;   -- vaga liberada para o resto do caminho
end $$;

create or replace function finish_ride(p_ride uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update rides set status = 'completed', finished_at = now()
   where id = p_ride and driver_id = auth.uid() and status = 'in_progress';
  if not found then raise exception 'not_allowed'; end if;
  update bookings set status = 'completed', dropped_at = coalesce(dropped_at, now())
   where ride_id = p_ride and status = 'boarded';
  update bookings set status = 'cancelled', cancelled_by = 'no_show', cancel_reason = 'Corrida encerrada sem embarque'
   where ride_id = p_ride and status = 'reserved';
  delete from driver_presence where user_id = auth.uid();
end $$;

-- Paradas pendentes da corrida, em ordem, para a navegação do motorista.
create or replace function driver_navigation(p_ride uuid) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_r rides; v_prog int; v_speed int; v_res jsonb;
begin
  select * into v_r from rides where id = p_ride and driver_id = auth.uid();
  if v_r.id is null then raise exception 'not_allowed'; end if;
  v_prog := ride_progress_m(p_ride);
  select avg_speed_kmh into v_speed from app_config;

  with acts as (
    select b.pickup_stop_id as stop_id, 'pickup' as kind, b.* from bookings b
     where b.ride_id = p_ride and b.status = 'reserved'
    union all
    select b.dropoff_stop_id, 'dropoff', b.* from bookings b
     where b.ride_id = p_ride and b.status in ('reserved', 'boarded')
  ), per_stop as (
    select a.stop_id, rs.seq, rs.distance_from_start_m dist, s.name, s.lat, s.lng,
           jsonb_agg(jsonb_build_object(
             'booking_id', a.id, 'kind', a.kind, 'status', a.status, 'pickup_mode', a.pickup_mode,
             'passenger', person_json(a.passenger_id)) order by a.kind, a.created_at) as actions  -- quem desce antes de quem sobe
      from acts a
      join ride_stops rs on rs.ride_id = p_ride and rs.stop_id = a.stop_id
      join stops s on s.id = a.stop_id
     group by a.stop_id, rs.seq, rs.distance_from_start_m, s.name, s.lat, s.lng
  )
  select jsonb_build_object(
    'ride', ride_json(p_ride),
    'route', st_asgeojson(v_r.route)::jsonb,
    'progress_m', v_prog,
    'destination', jsonb_build_object('lat', st_y(st_endpoint(v_r.route)), 'lng', st_x(st_endpoint(v_r.route)),
                                      'label', v_r.dest_label),
    'stops', coalesce((select jsonb_agg(jsonb_build_object(
               'stop_id', p.stop_id, 'name', p.name, 'lat', p.lat, 'lng', p.lng, 'seq', p.seq,
               'distance_m', p.dist,
               'eta', case when v_r.status = 'in_progress'
                           then now() + make_interval(secs => greatest(0, p.dist - v_prog) / (v_speed / 3.6))
                           else v_r.departure_at + make_interval(secs => p.dist / (v_speed / 3.6)) end,
               'actions', p.actions) order by p.seq) from per_stop p), '[]'::jsonb),
    'version', coalesce((select md5(string_agg(b.id::text || ':' || b.status, ',' order by b.id))
                           from bookings b where b.ride_id = p_ride and b.status <> 'cancelled'), '')
  ) into v_res;
  return v_res;
end $$;

-- ---------------------------------------------------------------------
-- Reservar com a corrida andando (só paradas à frente do carro)
-- ---------------------------------------------------------------------
create or replace function book_seat(p_ride uuid, p_pickup text, p_dropoff text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; v_ride rides; v_driver_gender gender;
  v_a ride_stops; v_b ride_stops; v_distance int; v_id uuid; v_ahead int;
begin
  select * into v_me from profiles where id = auth.uid();
  if v_me.id is null then raise exception 'not_authenticated'; end if;

  select * into v_ride from rides where id = p_ride for update;
  if v_ride.id is null or v_ride.status not in ('open', 'in_progress') then raise exception 'ride_unavailable'; end if;
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

  if v_ride.status = 'in_progress' then
    select ahead_min_m into v_ahead from app_config;
    if v_a.distance_from_start_m < ride_progress_m(p_ride) + v_ahead then raise exception 'pickup_already_passed'; end if;
  end if;

  v_distance := v_b.distance_from_start_m - v_a.distance_from_start_m;
  insert into bookings (ride_id, passenger_id, pickup_stop_id, dropoff_stop_id, distance_m, price_cents, boarding_code)
  values (p_ride, v_me.id, p_pickup, p_dropoff, v_distance, compute_price(v_distance),
          lpad(floor(random() * 10000)::int::text, 4, '0'))
  returning id into v_id;

  update rides set seats_available = seats_available - 1 where id = p_ride;
  return v_id;
end $$;

-- Motorista pode tirar passageiro que ainda não embarcou, mesmo com a corrida andando
create or replace function remove_passenger(p_booking uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_ride rides;
begin
  select * into v_b from bookings where id = p_booking for update;
  if v_b.id is null then raise exception 'not_allowed'; end if;
  select * into v_ride from rides where id = v_b.ride_id for update;
  if v_ride.driver_id is distinct from auth.uid() then raise exception 'not_allowed'; end if;
  if v_b.status <> 'reserved' or v_ride.status not in ('open', 'in_progress') then raise exception 'cannot_remove_passenger'; end if;

  update bookings
     set status = 'cancelled', cancelled_by = 'driver', cancel_reason = nullif(trim(p_reason), '')
   where id = p_booking;
  update rides set seats_available = seats_available + 1 where id = v_ride.id;
end $$;

-- ---------------------------------------------------------------------
-- Busca: também acha corrida já andando, se a parada ainda está à frente
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
    cross join lateral (select ride_progress_m(r.id) as prog) g
    -- Embarque: o carro (se estou pertinho da saída e ele ainda não saiu) ou a parada mais próxima
    cross join lateral (
      select s.id, s.name, s.lat, s.lng, rs.seq, rs.distance_from_start_m dist,
             round(st_distance(s.geog, v_from))::int walk_m,
             case when r.status = 'open' and s.ride_id = r.id and rs.seq = 1 and st_dwithin(s.geog, v_from, v_c.meet_radius_m)
                  then 'car' else 'stop' end as mode
      from ride_stops rs join stops s on s.id = rs.stop_id
      where rs.ride_id = r.id
        and (r.status = 'open' or rs.distance_from_start_m >= g.prog + v_c.ahead_min_m)
        and (
          (not s.meet_only and st_dwithin(s.geog, v_from, v_c.walk_radius_m))
          or (r.status = 'open' and s.ride_id = r.id and rs.seq = 1 and st_dwithin(s.geog, v_from, v_c.meet_radius_m)
              and r.departure_at > now() - interval '2 minutes')
        )
      order by (r.status = 'open' and s.ride_id = r.id and rs.seq = 1 and st_dwithin(s.geog, v_from, v_c.meet_radius_m)) desc,
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
      select case when r.status = 'in_progress'
                  then now() + make_interval(secs => greatest(0, pu.dist - g.prog) / (v_c.avg_speed_kmh / 3.6))
                  else r.departure_at + make_interval(secs => pu.dist / (v_c.avg_speed_kmh / 3.6)) end as eta,
             greatest(1, ceil(pu.walk_m::numeric / v_c.walk_m_per_min))::int as walk_min) e
    where r.status in ('open', 'in_progress') and r.seats_available > 0
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

revoke execute on function ride_progress_m(uuid) from public, anon, authenticated;
revoke execute on function start_ride(uuid), board_passenger(uuid), passenger_no_show(uuid), drop_passenger(uuid),
                           finish_ride(uuid), driver_navigation(uuid) from public, anon;
grant execute on function start_ride(uuid), board_passenger(uuid), passenger_no_show(uuid), drop_passenger(uuid),
                          finish_ride(uuid), driver_navigation(uuid), stop_eta(uuid, text) to authenticated;
