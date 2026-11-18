-- Faz os motoristas de teste "dirigirem" de verdade, como se tivessem o app aberto:
--  * na hora da saída, a corrida começa (in_progress);
--  * o carro anda pela rota a 30 km/h e manda a posição (aparece no mapa);
--  * quem reservou embarca quando o carro passa na parada e desce no destino;
--  * ao chegar, a corrida termina.
-- Rodado a cada 10 s pelo workflow "Motoristas de teste" (ações publicar e simular).
set search_path = public, extensions;

-- 1) começa as corridas que já deviam ter saído (até 3 h atrás)
update rides set status = 'in_progress', started_at = departure_at
 where driver_id::text like 'd0000000-0000-4000-8000-%'
   and status = 'open' and route is not null
   and departure_at <= now() and departure_at > now() - interval '3 hours';

-- 2) embarques e desembarques pelo caminho
with prog as (
  select r.id, (extract(epoch from now() - r.started_at) * (30 / 3.6))::int as m
    from rides r
   where r.driver_id::text like 'd0000000-0000-4000-8000-%' and r.status = 'in_progress')
update bookings b set status = 'boarded', boarded_at = now()
  from prog p, ride_stops rs
 where b.ride_id = p.id and b.status = 'reserved'
   and rs.ride_id = p.id and rs.stop_id = b.pickup_stop_id and rs.distance_from_start_m <= p.m;

with prog as (
  select r.id, (extract(epoch from now() - r.started_at) * (30 / 3.6))::int as m
    from rides r
   where r.driver_id::text like 'd0000000-0000-4000-8000-%' and r.status = 'in_progress')
update bookings b set status = 'completed', dropped_at = now()
  from prog p, ride_stops rs
 where b.ride_id = p.id and b.status = 'boarded'
   and rs.ride_id = p.id and rs.stop_id = b.dropoff_stop_id and rs.distance_from_start_m <= p.m;

-- 3) chegou: encerra
update rides set status = 'completed', finished_at = now()
 where driver_id::text like 'd0000000-0000-4000-8000-%'
   and status = 'in_progress'
   and extract(epoch from now() - started_at) * (30 / 3.6) >= distance_m;

-- 4) posição de cada motorista na corrida ativa dele (uma por motorista)
insert into driver_presence (user_id, lat, lng, heading, updated_at)
select r.driver_id, st_y(g.p), st_x(g.p), degrees(st_azimuth(g.p, g.ahead))::real, now()
from (select distinct driver_id from rides where driver_id::text like 'd0000000-0000-4000-8000-%') d
join rides r on r.id = active_ride_of(d.driver_id)
cross join lateral (
  select greatest(0, least(1,
           extract(epoch from now() - coalesce(r.started_at, r.departure_at)) * (30 / 3.6) / nullif(r.distance_m, 0))) as frac) f
cross join lateral (
  select st_lineinterpolatepoint(r.route, f.frac) as p,
         st_lineinterpolatepoint(r.route, least(1, f.frac + .003)) as ahead) g
where r.route is not null
on conflict (user_id) do update
  set lat = excluded.lat, lng = excluded.lng,
      heading = coalesce(excluded.heading, driver_presence.heading), updated_at = now();
