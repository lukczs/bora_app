-- =====================================================================
-- BORA — 0014: só oferece parada onde dá tempo de chegar a pé
--
-- Antes a busca só garantia que o carro ainda não tinha passado pela
-- parada. Agora ela escolhe a parada mais perto ONDE O PASSAGEIRO CHEGA A PÉ
-- ANTES DO CARRO (com a folga de pickup_buffer_min). Quem mora do lado da
-- parada pode pegar o carro bem próximo; quem está mais longe vê só
-- paradas mais à frente.
-- =====================================================================

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
        -- dá tempo de chegar a pé (com folga) antes do carro passar?
        and (case when r.status = 'in_progress'
                  then now() + make_interval(secs => greatest(0, rs.distance_from_start_m - g.prog) / (v_c.avg_speed_kmh / 3.6))
                  else r.departure_at + make_interval(secs => rs.distance_from_start_m / (v_c.avg_speed_kmh / 3.6)) end)
            - make_interval(mins => v_c.pickup_buffer_min
                                   + greatest(1, ceil(st_distance(s.geog, v_from) / v_c.walk_m_per_min))::int)
            >= now()
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
