-- =====================================================================
-- BORA — 0017: avaliação depois da corrida
-- Passageiro avalia o motorista e o motorista avalia cada passageiro
-- (1 a 5 estrelas, etiquetas rápidas e comentário opcional).
-- A média fica em profiles.rating_avg / rating_count.
-- =====================================================================

create table if not exists ratings (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null references bookings(id) on delete cascade,
  ride_id     uuid not null references rides(id) on delete cascade,
  rater_id    uuid not null references profiles(id) on delete cascade,
  rated_id    uuid not null references profiles(id) on delete cascade,
  rated_role  text not null check (rated_role in ('driver', 'passenger')),
  stars       int  not null check (stars between 1 and 5),
  tags        text[] not null default '{}',
  comment     text check (char_length(comment) <= 300),
  created_at  timestamptz not null default now(),
  unique (booking_id, rater_id)
);
create index if not exists ratings_rated_idx on ratings (rated_id);
alter table ratings enable row level security;
-- ninguém lê a tabela direto; só pelas funções abaixo
drop policy if exists ratings_none on ratings;

-- Avaliações que eu ainda devo (últimos 7 dias)
create or replace function pending_ratings() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.at desc), '[]'::jsonb) from (
    -- como passageiro: avaliar o motorista
    select jsonb_build_object('booking_id', b.id, 'ride_id', r.id, 'rated_role', 'driver',
             'person', person_json(r.driver_id), 'when', coalesce(b.dropped_at, r.finished_at),
             'from', (select name from stops where id = b.pickup_stop_id),
             'to', (select name from stops where id = b.dropoff_stop_id)) j,
           coalesce(b.dropped_at, r.finished_at) at
      from bookings b join rides r on r.id = b.ride_id
     where b.passenger_id = auth.uid() and b.status = 'completed'
       and coalesce(b.dropped_at, r.finished_at) > now() - interval '7 days'
       and not exists (select 1 from ratings x where x.booking_id = b.id and x.rater_id = auth.uid())
    union all
    -- como motorista: avaliar cada passageiro que levei
    select jsonb_build_object('booking_id', b.id, 'ride_id', r.id, 'rated_role', 'passenger',
             'person', person_json(b.passenger_id), 'when', coalesce(b.dropped_at, r.finished_at),
             'from', (select name from stops where id = b.pickup_stop_id),
             'to', (select name from stops where id = b.dropoff_stop_id)),
           coalesce(b.dropped_at, r.finished_at)
      from bookings b join rides r on r.id = b.ride_id
     where r.driver_id = auth.uid() and b.status = 'completed'
       and coalesce(b.dropped_at, r.finished_at) > now() - interval '7 days'
       and not exists (select 1 from ratings x where x.booking_id = b.id and x.rater_id = auth.uid())
  ) x;
$$;

create or replace function rate_trip(p_booking uuid, p_stars int, p_tags text[] default '{}', p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_r rides; v_rated uuid; v_role text;
begin
  select * into v_b from bookings where id = p_booking;
  if v_b.id is null or v_b.status <> 'completed' then raise exception 'cannot_rate'; end if;
  select * into v_r from rides where id = v_b.ride_id;
  if auth.uid() = v_b.passenger_id then v_rated := v_r.driver_id; v_role := 'driver';
  elsif auth.uid() = v_r.driver_id then v_rated := v_b.passenger_id; v_role := 'passenger';
  else raise exception 'not_allowed'; end if;
  if p_stars not between 1 and 5 then raise exception 'invalid_rating'; end if;

  insert into ratings (booking_id, ride_id, rater_id, rated_id, rated_role, stars, tags, comment)
  values (p_booking, v_r.id, auth.uid(), v_rated, v_role, p_stars, coalesce(p_tags, '{}'),
          nullif(left(trim(coalesce(p_comment, '')), 300), ''))
  on conflict (booking_id, rater_id) do update
    set stars = excluded.stars, tags = excluded.tags, comment = excluded.comment, created_at = now();

  update profiles p set rating_avg = s.avg, rating_count = s.n
    from (select round(avg(stars)::numeric, 2) avg, count(*) n from ratings where rated_id = v_rated) s
   where p.id = v_rated;
end $$;

revoke execute on function pending_ratings(), rate_trip(uuid, int, text[], text) from public, anon;
grant execute on function pending_ratings(), rate_trip(uuid, int, text[], text) to authenticated;
