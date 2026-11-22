-- =====================================================================
-- BORA — 0016: limpeza automática (roda sozinha a cada 10 minutos)
--
--  * Evento terminado sai da lista: 2 h depois do fim previsto vira
--    'ended' (dá tempo das caronas de volta).
--  * Corrida esquecida em andamento (motorista fechou o app sem encerrar):
--    quando passa do dobro do tempo previsto + 30 min e o GPS parou há
--    30 min, é encerrada como o botão faria.
--  * Viagem que nunca começou: 6 h depois do horário, é cancelada e as
--    reservas avisam "A viagem não aconteceu".
-- =====================================================================

create extension if not exists pg_cron;

alter table events drop constraint if exists events_status_check;
alter table events add constraint events_status_check check (status in ('active', 'cancelled', 'ended'));

create or replace function housekeeping() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_events int; v_finished int; v_expired int; v_speed int; v_ids uuid[];
begin
  select avg_speed_kmh into v_speed from app_config;

  update events set status = 'ended'
   where status = 'active' and ends_at < now() - interval '2 hours';
  get diagnostics v_events = row_count;

  -- corridas esquecidas
  select coalesce(array_agg(r.id), '{}') into v_ids
    from rides r
    left join driver_presence p on p.user_id = r.driver_id
   where r.status = 'in_progress'
     and now() > coalesce(r.started_at, r.departure_at)
                 + make_interval(secs => 2 * r.distance_m / (v_speed / 3.6)) + interval '30 minutes'
     and (p.user_id is null or p.updated_at < now() - interval '30 minutes');
  update rides set status = 'completed', finished_at = now() where id = any(v_ids);
  v_finished := cardinality(v_ids);
  update bookings set status = 'completed', dropped_at = coalesce(dropped_at, now())
   where ride_id = any(v_ids) and status = 'boarded';
  update bookings set status = 'cancelled', cancelled_by = 'no_show', cancel_reason = 'Corrida encerrada sem embarque'
   where ride_id = any(v_ids) and status = 'reserved';

  -- viagens que nunca começaram
  select coalesce(array_agg(id), '{}') into v_ids
    from rides where status = 'open' and departure_at < now() - interval '6 hours';
  update rides set status = 'cancelled' where id = any(v_ids);
  v_expired := cardinality(v_ids);
  update bookings set status = 'cancelled', cancelled_by = 'ride', cancel_reason = 'A viagem não aconteceu'
   where ride_id = any(v_ids) and status = 'reserved';

  return jsonb_build_object('events_ended', v_events, 'rides_finished', v_finished, 'rides_expired', v_expired);
end $$;

revoke execute on function housekeeping() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'bora-limpeza';
select cron.schedule('bora-limpeza', '*/10 * * * *', 'select public.housekeeping()');
