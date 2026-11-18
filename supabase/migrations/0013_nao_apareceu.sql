-- "Não apareceu" (passenger_no_show / finish_ride) grava cancelled_by = 'no_show',
-- que a regra antiga da tabela não aceitava. Achado pelo teste de ponta a ponta.
alter table bookings drop constraint if exists bookings_cancelled_by_check;
alter table bookings add constraint bookings_cancelled_by_check
  check (cancelled_by in ('passenger', 'driver', 'ride', 'no_show'));
