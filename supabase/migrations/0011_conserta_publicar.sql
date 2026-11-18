-- Conserta "criar viagem" pelo app.
-- A API do Supabase (PostgREST) carrega a extensão safeupdate, que barra
-- DELETE sem WHERE. O rebuild_ride_stops limpava uma tabela temporária com
-- "delete from _on_route" e a publicação caía com 400. Pelo psql (seed dos
-- motoristas de teste) funcionava, por isso passou despercebido.
-- Agora a função não usa tabela temporária: tudo sai de uma consulta só.

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

  -- Paradas de verdade que ficam na rota
  with on_route as (
    select s.geog from stops s
     where s.ride_id is null and s.active and s.boardable
       and st_dwithin(s.geog, v_r.route::geography, v_snap))
  select exists (select 1 from on_route where st_dwithin(geog, v_start, v_walk)),
         not exists (select 1 from on_route where st_dwithin(geog, v_end, v_walk))
    into v_near_o, v_need_d;

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
    select s.id, st_linelocatepoint(v_r.route, s.geog::geometry) as frac, 1 as tie
      from stops s
     where s.ride_id is null and s.active and s.boardable
       and st_dwithin(s.geog, v_r.route::geography, v_snap)
    union all select v_o, 0, 0
    union all select v_d, 1, 2 where v_need_d
  ) x;
  get diagnostics v_count = row_count;

  update rides set path = coalesce((select array_agg(stop_id order by seq) from ride_stops where ride_id = p_ride), '{}')
   where id = p_ride;
  return v_count;
end $$;

revoke execute on function rebuild_ride_stops(uuid) from public, anon, authenticated;
