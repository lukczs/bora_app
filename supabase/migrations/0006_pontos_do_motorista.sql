-- =====================================================================
-- BORA — 0006: saída e chegada do motorista como pontos de embarque
--
-- Problema (visto com os motoristas de teste): a rota Senac -> Condomínio RK
-- passa a 126 m do Senac, mas a parada de ônibus mais próxima do caminho
-- fica a 3,6 km. Ninguém na faculdade conseguia pegar a carona.
--
-- Agora: se não existir parada a até walk_radius_m (800 m) da saída ou da
-- chegada, o próprio ponto vira embarque ("Saída · Faculdade Senac").
-- Esses pontos ficam presos à viagem (somem com ela) e não aparecem no
-- mapa geral de paradas.
-- =====================================================================

alter table stops add column if not exists ride_id uuid references rides (id) on delete cascade;
create index if not exists stops_ride_idx on stops (ride_id) where ride_id is not null;

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

  -- Pontos do motorista só quando não há parada de verdade por perto
  v_need_o := not exists (select 1 from stops s where s.ride_id is null and s.active and s.boardable
                                                   and st_dwithin(s.geog, v_start, v_walk));
  v_need_d := not exists (select 1 from stops s where s.ride_id is null and s.active and s.boardable
                                                   and st_dwithin(s.geog, v_end, v_walk));
  if v_need_o then
    insert into stops (id, name, region, lat, lng, boardable, active, source, ride_id)
    values (v_o, left('Saída · ' || coalesce(v_r.origin_label, 'ponto do motorista'), 80), 'Ponto do motorista',
            st_y(st_startpoint(v_r.route)), st_x(st_startpoint(v_r.route)), true, true, 'ride', p_ride)
    on conflict (id) do update set name = excluded.name, lat = excluded.lat, lng = excluded.lng;
  end if;
  if v_need_d then
    insert into stops (id, name, region, lat, lng, boardable, active, source, ride_id)
    values (v_d, left('Chegada · ' || coalesce(v_r.dest_label, 'ponto do motorista'), 80), 'Ponto do motorista',
            st_y(st_endpoint(v_r.route)), st_x(st_endpoint(v_r.route)), true, true, 'ride', p_ride)
    on conflict (id) do update set name = excluded.name, lat = excluded.lat, lng = excluded.lng;
  end if;

  insert into ride_stops (ride_id, stop_id, seq, distance_from_start_m)
  select p_ride, x.id, row_number() over (order by x.frac, x.tie), (x.frac * v_len)::int
  from (
    select s.id, st_linelocatepoint(v_r.route, s.geog::geometry) as frac, 1 as tie
      from stops s
     where s.ride_id is null and s.active and s.boardable
       and st_dwithin(s.geog, v_r.route::geography, v_snap)
    union all select v_o, 0, 0 where v_need_o
    union all select v_d, 1, 2 where v_need_d
  ) x;
  get diagnostics v_count = row_count;

  update rides set path = coalesce((select array_agg(stop_id order by seq) from ride_stops where ride_id = p_ride), '{}')
   where id = p_ride;
  return v_count;
end $$;

-- Mapa geral: só paradas de verdade
create or replace function stops_in_view(p_south double precision, p_west double precision,
                                         p_north double precision, p_east double precision)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'region', s.region,
                                               'lat', s.lat, 'lng', s.lng, 'boardable', s.boardable,
                                               'has_shelter', s.has_shelter, 'is_lit', s.is_lit)), '[]'::jsonb)
  from (select * from stops
         where active and boardable and ride_id is null
           and lat between p_south and p_north and lng between p_west and p_east
         limit 300) s;
$$;

create or replace function stops_near(p_lat double precision, p_lng double precision, p_radius_m int default 1000)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'name', s.name, 'region', s.region, 'lat', s.lat, 'lng', s.lng,
           'distance_m', round(st_distance(s.geog, p.g))::int) order by st_distance(s.geog, p.g)), '[]'::jsonb)
  from (select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography g) p
  join stops s on s.active and s.boardable and s.ride_id is null and st_dwithin(s.geog, p.g, least(p_radius_m, 5000));
$$;

revoke execute on function rebuild_ride_stops(uuid) from public, anon, authenticated;

-- Recalcula as viagens abertas que já têm rota
select rebuild_ride_stops(id) from rides where route is not null and status in ('open', 'in_progress');
