-- =====================================================================
-- BORA — 0007: ajuste da 0006
-- O ponto do motorista vira embarque quando não há parada DA ROTA perto da
-- saída/chegada (antes contava qualquer parada perto, mesmo em outra rua).
-- =====================================================================
create or replace function rebuild_ride_stops(p_ride uuid) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_r rides; v_len int; v_snap int; v_walk int; v_count int;
  v_start geography; v_end geography; v_o text; v_d text; v_need_o boolean; v_need_d boolean;
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

  -- paradas de verdade que ficam no caminho
  create temp table if not exists _on_route (id text, frac double precision, geog geography) on commit drop;
  delete from _on_route;
  insert into _on_route
  select s.id, st_linelocatepoint(v_r.route, s.geog::geometry), s.geog
    from stops s
   where s.ride_id is null and s.active and s.boardable
     and st_dwithin(s.geog, v_r.route::geography, v_snap);

  v_need_o := not exists (select 1 from _on_route where st_dwithin(geog, v_start, v_walk));
  v_need_d := not exists (select 1 from _on_route where st_dwithin(geog, v_end, v_walk));

  if v_need_o then
    insert into stops (id, name, region, lat, lng, boardable, active, source, ride_id)
    values (v_o, left('Saída · ' || coalesce(v_r.origin_label, 'ponto do motorista'), 80), 'Ponto do motorista',
            st_y(st_startpoint(v_r.route)), st_x(st_startpoint(v_r.route)), true, true, 'ride', p_ride)
    on conflict (id) do update set name = excluded.name, lat = excluded.lat, lng = excluded.lng, active = true;
  end if;
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
    union all select v_o, 0, 0 where v_need_o
    union all select v_d, 1, 2 where v_need_d
  ) x;
  get diagnostics v_count = row_count;

  update rides set path = coalesce((select array_agg(stop_id order by seq) from ride_stops where ride_id = p_ride), '{}')
   where id = p_ride;
  return v_count;
end $$;

revoke execute on function rebuild_ride_stops(uuid) from public, anon, authenticated;

select rebuild_ride_stops(id) from rides where route is not null and status in ('open', 'in_progress');
