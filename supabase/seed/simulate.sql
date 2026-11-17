-- Move os carros de teste pela rota real (30 km/h a partir do horário de saída).
-- Antes da saída o carro fica parado na origem; depois de chegar, no destino.
set search_path = public, extensions;
insert into driver_presence (user_id, lat, lng, heading, updated_at)
select r.driver_id, st_y(g.p), st_x(g.p), degrees(st_azimuth(g.p, g.ahead))::real, now()
from rides r
cross join lateral (
  select greatest(0, least(1,
           extract(epoch from now() - r.departure_at) * (30 / 3.6) / nullif(r.distance_m, 0))) as frac) f
cross join lateral (
  select st_lineinterpolatepoint(r.route, f.frac) as p,
         st_lineinterpolatepoint(r.route, least(1, f.frac + .003)) as ahead) g
where r.driver_id::text like 'd0000000-0000-4000-8000-%'
  and r.status = 'open' and r.route is not null
on conflict (user_id) do update
  set lat = excluded.lat, lng = excluded.lng,
      heading = coalesce(excluded.heading, driver_presence.heading), updated_at = now();
