-- Apaga as contas de teste automático (qa1..qa3@bora.dev) e tudo que elas criaram.
begin;
create temp table _qa on commit drop as
  select ('e0000000-0000-4000-8000-00000000000' || n)::uuid as id from generate_series(1, 3) n;
delete from bookings where passenger_id in (select id from _qa)
   or ride_id in (select id from rides where driver_id in (select id from _qa));
delete from rides where driver_id in (select id from _qa);
delete from communities where created_by in (select id from _qa);
delete from auth.users where id in (select id from _qa);
commit;
