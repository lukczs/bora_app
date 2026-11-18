-- Todas as paradas de ônibus de uma vez (~2 mil), para o app filtrar no
-- próprio celular enquanto o mapa mexe. Antes cada movimento esperava uma
-- consulta ao servidor (stops_in_view, que ainda cortava em 300 sem ordem)
-- e as paradas demoravam ou nem apareciam.
create or replace function all_stops() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'name', s.name, 'region', s.region, 'lat', s.lat, 'lng', s.lng,
           'boardable', true, 'has_shelter', s.has_shelter, 'is_lit', s.is_lit)), '[]'::jsonb)
  from stops s
  where s.active and s.boardable and s.ride_id is null;
$$;
revoke execute on function all_stops() from public, anon;
grant execute on function all_stops() to authenticated;
