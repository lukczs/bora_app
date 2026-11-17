"""
Motoristas de teste do Bora.

Cria (ou recria) 5 contas de teste, calcula a rota real de cada uma na
OpenRouteService e publica pela MESMA função que o app usa
(publish_ride_route). Assim dá para ver se o algoritmo de rota aguenta.

Uso (no GitHub Actions):
  python3 demo_rides.py publicar <minutos_ate_sair>  -> gera seed.sql
  python3 demo_rides.py remover                      -> gera seed.sql

Variáveis: ORS_API_KEY.
Todas as contas de teste têm id d0000000-0000-4000-8000-00000000000N
e e-mail testeN@bora.dev, então dá para apagar tudo depois.
"""
import json
import sys
import urllib.parse
import urllib.request

ORS = "https://api.openrouteservice.org"
KEY = __import__("os").environ.get("ORS_API_KEY", "")

# (nome, gênero, carro, placa, cor, vagas, origem, destino)
# origem/destino: (rótulo, lat, lng, busca opcional para conferir no geocoder)
DRIVERS = [
    ("Mariana Teste", "female", "Fiat Argo", "TST1A01", "Prata", 3,
     ("Faculdade Senac · 713/913 Sul", -15.819945, -47.921497, None),
     ("Condomínio RK · Sobradinho", -15.6765, -47.7480, "Condomínio RK, Sobradinho")),
    ("Rafael Teste", "male", "VW Gol", "TST1A02", "Branco", 3,
     ("SQS 107 · Asa Sul", -15.8080, -47.8940, None),
     ("Candangolândia", -15.8510, -47.9505, None)),
    ("Bruno Teste", "male", "Chevrolet Onix", "TST1A03", "Preto", 4,
     ("Ceilândia Centro", -15.8190, -48.1080, None),
     ("Esplanada dos Ministérios", -15.7990, -47.8640, None)),
    ("Júlia Teste", "female", "Hyundai HB20", "TST1A04", "Vermelho", 3,
     ("Gama · Setor Central", -16.0150, -48.0630, None),
     ("Rodoviária do Plano Piloto", -15.7938, -47.8828, None)),
    ("Diego Teste", "male", "Renault Kwid", "TST1A05", "Azul", 3,
     ("Rodoviária de Planaltina", -15.6210, -47.6520, None),
     ("UnB · Darcy Ribeiro", -15.7632, -47.8706, None)),
]


def uid(i):
    return f"d0000000-0000-4000-8000-{i:012d}"


def http(url, body=None):
    headers = {"Authorization": KEY, "Content-Type": "application/json",
               "Accept": "application/json, application/geo+json"}
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def geocode(text, fallback):
    """Confere o ponto no geocoder; usa o do arquivo se o resultado parecer errado."""
    lat0, lng0 = fallback
    try:
        q = urllib.parse.urlencode({"text": text, "boundary.country": "BR", "size": 1,
                                    "boundary.rect.min_lon": -48.3, "boundary.rect.max_lon": -47.3,
                                    "boundary.rect.min_lat": -16.1, "boundary.rect.max_lat": -15.5})
        f = http(f"{ORS}/geocode/search?{q}")["features"]
        if f:
            lng, lat = f[0]["geometry"]["coordinates"]
            label = f[0]["properties"].get("label")
            # aceita se cair a menos de ~8 km do ponto esperado
            if abs(lat - lat0) < .07 and abs(lng - lng0) < .07:
                print(f"   geocoder: {label} ({lat:.5f}, {lng:.5f})", file=sys.stderr)
                return lat, lng
            print(f"   geocoder devolveu {label} longe demais; mantendo o ponto do arquivo", file=sys.stderr)
    except Exception as e:  # noqa: BLE001
        print(f"   geocoder falhou ({e}); mantendo o ponto do arquivo", file=sys.stderr)
    return lat0, lng0


def route(a, b):
    body = {"coordinates": [[a[1], a[0]], [b[1], b[0]]], "instructions": False}
    f = http(f"{ORS}/v2/directions/driving-car/geojson", body)["features"][0]
    s = f["properties"]["summary"]
    return f["geometry"], s["distance"], s["duration"]


def q(s):
    return "'" + str(s).replace("'", "''") + "'"


def cleanup_sql():
    ids = ",".join(q(uid(i + 1)) for i in range(len(DRIVERS)))
    return f"""
delete from driver_presence where user_id in ({ids});
delete from ride_messages where ride_id in (select id from rides where driver_id in ({ids}));
delete from bookings where ride_id in (select id from rides where driver_id in ({ids}));
delete from ride_stops where ride_id in (select id from rides where driver_id in ({ids}));
delete from ride_communities where ride_id in (select id from rides where driver_id in ({ids}));
delete from rides where driver_id in ({ids});
delete from vehicles where owner_id in ({ids});
delete from auth.users where id in ({ids});
"""


def publish_sql(minutes):
    out = ["begin;", "set local search_path = public, extensions;", cleanup_sql()]
    for i, (name, gender, car, plate, color, seats, a, b) in enumerate(DRIVERS, start=1):
        print(f"{i}. {name}: {a[0]} -> {b[0]}", file=sys.stderr)
        pa = geocode(a[3], (a[1], a[2])) if a[3] else (a[1], a[2])
        pb = geocode(b[3], (b[1], b[2])) if b[3] else (b[1], b[2])
        geom, dist, dur = route(pa, pb)
        print(f"   rota: {dist/1000:.1f} km, {dur/60:.0f} min, {len(geom['coordinates'])} pontos", file=sys.stderr)
        u = uid(i)
        dep = minutes + (i - 1) * 3
        out.append(f"""
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
values ({q(u)}, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'teste{i}@bora.dev', '', now(), '{{"provider":"email","providers":["email"]}}', '{{"demo":true}}',
        now(), now(), '', '', '', '');
update profiles set full_name = {q(name)}, cpf = {q(f'0000000000{i}')}, birth_date = '1995-01-01',
       gender = {q(gender)}, identity_status = 'approved', onboarding_done = true,
       rating_avg = {4.6 + i / 20:.2f}, rating_count = {10 + i * 7}
 where id = {q(u)};
insert into emergency_contacts (user_id, name, phone, relation) values ({q(u)}, 'Contato Teste', '61900000000', 'outro');
insert into vehicles (owner_id, plate, brand, model, color, seats)
values ({q(u)}, {q(plate)}, {q(car.split()[0])}, {q(' '.join(car.split()[1:]))}, {q(color)}, {seats});
select set_config('request.jwt.claim.sub', {q(u)}, true);
select set_config('request.jwt.claims', {q(json.dumps({'sub': u, 'role': 'authenticated'}))}, true);
select '{name}' as motorista, publish_ride_route(
  (select id from vehicles where owner_id = {q(u)}),
  {q(json.dumps(geom))}::jsonb, {q(a[0])}, {q(b[0])},
  now() + interval '{dep} minutes', {seats}, '{{1,2,3,4,5}}', false, null) as resultado;
""")
    out.append("commit;")
    return "\n".join(out)


if __name__ == "__main__":
    action = sys.argv[1]
    if action == "remover":
        print("begin;\n" + cleanup_sql() + "\ncommit;")
    else:
        if not KEY:
            sys.exit("Falta ORS_API_KEY")
        print(publish_sql(int(sys.argv[2]) if len(sys.argv) > 2 else 10))
