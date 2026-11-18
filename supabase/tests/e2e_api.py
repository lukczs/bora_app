"""
Teste de ponta a ponta do Bora pela API de verdade (a mesma que o app usa).

Entra com 3 contas de teste (qa1 motorista, qa2 passageira, qa3 passageiro),
faz o cadastro e passa por cada função do app, uma por vez, com os mesmos
nomes e formatos de parâmetro do lib/data/bora_store.dart:

  cadastro -> carro -> publicar viagem -> buscar -> reservar -> acompanhar
  -> cancelar/remover -> comunidades -> eventos -> corrida (iniciar,
  navegação, passageiro novo no caminho, embarque, não apareceu,
  desembarque, encerrar)

Variáveis: SUPABASE_URL, SUPABASE_ANON_KEY, ORS_API_KEY, QA_PASSWORD.
Sai com erro se alguma etapa falhar; o resumo vai para o log e para
$GITHUB_STEP_SUMMARY.
"""
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.request

URL = os.environ["SUPABASE_URL"].rstrip("/")
ANON = os.environ["SUPABASE_ANON_KEY"]
ORS_KEY = os.environ.get("ORS_API_KEY", "")
PW = os.environ["QA_PASSWORD"]

results = []  # (etapa, ok, ms, detalhe)


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status
        self.message = message


def _http(method, url, body=None, headers=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            j = json.loads(raw)
            msg = j.get("message") or j.get("msg") or j.get("error_description") or raw
        except Exception:  # noqa: BLE001
            msg = raw
        raise ApiError(e.code, msg) from None


class User:
    def __init__(self, label, email):
        self.label = label
        tok = _http("POST", f"{URL}/auth/v1/token?grant_type=password",
                    {"email": email, "password": PW},
                    {"apikey": ANON, "Content-Type": "application/json"})
        self.token = tok["access_token"]
        self.id = tok["user"]["id"]

    def _h(self, extra=None):
        h = {"apikey": ANON, "Authorization": f"Bearer {self.token}", "Content-Type": "application/json"}
        h.update(extra or {})
        return h

    def rpc(self, name, params=None):
        return _http("POST", f"{URL}/rest/v1/rpc/{name}", params or {}, self._h())

    def rest(self, method, path, body=None, prefer=None):
        return _http(method, f"{URL}/rest/v1/{path}", body, self._h({"Prefer": prefer} if prefer else None))


def step(name, fn, expect_error=None):
    """Roda uma etapa. Com expect_error, passa só se a API recusar com essa mensagem."""
    t0 = time.time()
    try:
        value = fn()
        ms = int((time.time() - t0) * 1000)
        if expect_error:
            results.append((name, False, ms, f"deveria recusar com '{expect_error}', mas aceitou"))
            return None
        results.append((name, True, ms, ""))
        return value
    except ApiError as e:
        ms = int((time.time() - t0) * 1000)
        if expect_error and expect_error in e.message:
            results.append((name, True, ms, f"recusou como esperado: {expect_error}"))
        else:
            results.append((name, False, ms, str(e)))
        return None
    except Exception as e:  # noqa: BLE001
        results.append((name, False, int((time.time() - t0) * 1000), f"{type(e).__name__}: {e}"))
        return None


def require(cond, msg):
    if not cond:
        raise AssertionError(msg)


def iso(d):
    return d.astimezone(dt.timezone.utc).isoformat()


def ors_route(a, b):
    """Mesma chamada do RoutingService do app (geojson, sem instruções)."""
    body = {"coordinates": [[a[1], a[0]], [b[1], b[0]]], "instructions": False}
    f = _http("POST", "https://api.openrouteservice.org/v2/directions/driving-car/geojson", body,
              {"Authorization": ORS_KEY, "Content-Type": "application/json",
               "Accept": "application/json, application/geo+json"})["features"][0]
    return f["geometry"]


def ors_nav(points):
    """Rota com instruções em português (usada na navegação do motorista)."""
    body = {"coordinates": [[p[1], p[0]] for p in points], "instructions": True, "language": "pt"}
    f = _http("POST", "https://api.openrouteservice.org/v2/directions/driving-car/geojson", body,
              {"Authorization": ORS_KEY, "Content-Type": "application/json",
               "Accept": "application/json, application/geo+json"})["features"][0]
    return f


NOW = dt.datetime.now(dt.timezone.utc)
ASA_SUL_107 = (-15.8080, -47.8940)
CANDANGOLANDIA = (-15.8510, -47.9505)
STADIUM = (-15.7835, -47.8992)


def main():
    # ------------------------------------------------------------------ entrar
    drv = step("Login motorista (qa1)", lambda: User("motorista", "qa1@bora.dev"))
    p1 = step("Login passageira (qa2)", lambda: User("passageira", "qa2@bora.dev"))
    p2 = step("Login passageiro (qa3)", lambda: User("passageiro", "qa3@bora.dev"))
    if not (drv and p1 and p2):
        return

    # --------------------------------------------------------------- cadastro
    people = [(drv, "Motorista", "QA", "male", "99999999001"),
              (p1, "Passageira", "QA", "female", "99999999002"),
              (p2, "Passageiro", "QA", "male", "99999999003")]
    for u, first, last, gender, cpf in people:
        n = u.label
        step(f"[{n}] my_profile (novo)", lambda u=u: require(u.rpc("my_profile")["onboarding_done"] is False, "já vinha pronto"))
        step(f"[{n}] save_basic_profile", lambda u=u, f=first, l=last: u.rpc("save_basic_profile", {"p_first_name": f, "p_last_name": l, "p_language": "pt-BR"}))
        step(f"[{n}] accept_terms", lambda u=u: u.rpc("accept_terms"))
        step(f"[{n}] set_payment_pref", lambda u=u: u.rpc("set_payment_pref", {"p_pref": "pix"}))
        step(f"[{n}] submit_identity", lambda u=u, c=cpf, g=gender: u.rpc("submit_identity", {"p_cpf": c, "p_birth_date": "1995-05-20", "p_gender": g, "p_women_only_pref": False}))
        step(f"[{n}] save_emergency_contact", lambda u=u: u.rpc("save_emergency_contact", {"p_name": "Contato QA", "p_phone": "61999990000", "p_relation": "família"}))
        step(f"[{n}] submit_identity_documents", lambda u=u: u.rpc("submit_identity_documents"))
        step(f"[{n}] finish_onboarding", lambda u=u: u.rpc("finish_onboarding"))
        step(f"[{n}] my_profile (pronto)", lambda u=u: require(u.rpc("my_profile")["onboarding_done"] is True, "cadastro não terminou"))

    # ------------------------------------------------------------------ carro
    def add_car():
        drv.rest("POST", "vehicles", {"plate": "QAA1A11", "brand": "Fiat", "model": "Argo", "color": "Prata", "seats": 4})
        rows = drv.rest("GET", "vehicles?select=*&order=brand")
        require(len(rows) == 1, f"esperava 1 carro, veio {len(rows)}")
        return rows[0]["id"]
    car = step("Cadastrar carro (insert vehicles)", add_car)
    step("Editar carro (update vehicles)", lambda: drv.rest("PATCH", f"vehicles?id=eq.{car}", {"seats": 3}))

    def add_delete_car():
        drv.rest("POST", "vehicles", {"plate": "QAB2B22", "brand": "VW", "model": "Gol", "color": "Branco", "seats": 4})
        other = [v for v in drv.rest("GET", "vehicles?select=*") if v["plate"] == "QAB2B22"][0]["id"]
        drv.rest("DELETE", f"vehicles?id=eq.{other}")
        require(len(drv.rest("GET", "vehicles?select=*")) == 1, "carro não foi apagado")
    step("Apagar carro (delete vehicles)", add_delete_car)
    step("Passageira não vê carro dos outros", lambda: require(p1.rest("GET", "vehicles?select=*") == [], "vazou carro"))

    # --------------------------------------------------- dados do mapa / grafo
    step("Paradas do grafo (stops source=manual)", lambda: p1.rest("GET", "stops?select=*&source=eq.manual"))
    step("Ligações do grafo (stop_links)", lambda: p1.rest("GET", "stop_links?select=*"))
    stops_view = step("stops_in_view (Asa Sul)", lambda: p1.rpc("stops_in_view", {"p_south": -15.82, "p_west": -47.91, "p_north": -15.80, "p_east": -47.88}))
    step("stops_in_view trouxe paradas", lambda: require(stops_view and len(stops_view) > 0, "nenhuma parada"))
    if stops_view:
        step("stops_by_ids", lambda: require(len(p1.rpc("stops_by_ids", {"p_ids": [stops_view[0]["id"]]})) == 1, "não achou"))

    # -------------------------------------------------------- publicar viagem
    route = step("Rota no OpenRouteService (107 Sul -> Candangolândia)", lambda: ors_route(ASA_SUL_107, CANDANGOLANDIA))
    if not (car and route):
        return
    step("demand_near_route", lambda: drv.rpc("demand_near_route", {"p_route": route}))

    def publish(minutes, label):
        r = drv.rpc("publish_ride_route", {
            "p_vehicle": car, "p_route": route, "p_origin_label": f"SQS 107 ({label})", "p_dest_label": "Candangolândia",
            "p_departure": iso(NOW + dt.timedelta(minutes=minutes)), "p_seats": 3, "p_recurring": [],
            "p_women_only": False, "p_communities": None})
        require(r["stops"] >= 2, f"poucas paradas: {r}")
        return r["ride_id"]
    ride_a = step("CRIAR VIAGEM A (publish_ride_route, sai em 10 min)", lambda: publish(10, "A"))
    ride_b = step("CRIAR VIAGEM B (publish_ride_route, sai em 3 h)", lambda: publish(180, "B"))
    if not ride_a:
        return
    step("my_rides mostra as viagens", lambda: require({ride_a, ride_b} <= {r["id"] for r in drv.rpc("my_rides")}, "viagem sumiu"))
    step("update_ride (editar horário e vagas)", lambda: drv.rpc("update_ride", {"p_ride": ride_b, "p_departure": iso(NOW + dt.timedelta(minutes=200)), "p_seats": 2, "p_recurring": [1, 3]}))
    step("ride_route", lambda: require(drv.rpc("ride_route", {"p_ride": ride_a})["type"] == "LineString", "rota vazia"))

    # ----------------------------------------------------------- buscar e reservar
    def find(user, ride, frm=(-15.8095, -47.8955), to=(-15.8495, -47.9480)):
        offers = user.rpc("search_rides_near", {"p_from_lat": frm[0], "p_from_lng": frm[1], "p_to_lat": to[0], "p_to_lng": to[1], "p_only_my_communities": False})
        mine = [o for o in offers if o["ride"]["id"] == ride]
        require(mine, f"não achou a viagem entre {len(offers)} ofertas")
        return mine[0]
    offer_a = step("BUSCAR CARONA (search_rides_near acha a viagem A)", lambda: find(p1, ride_a))
    booking_p1 = None
    if offer_a:
        booking_p1 = step("RESERVAR (book_seat na A)", lambda: p1.rpc("book_seat", {"p_ride": ride_a, "p_pickup": offer_a["pickup_stop_id"], "p_dropoff": offer_a["dropoff_stop_id"]}))
        step("Reservar de novo é recusado", lambda: p1.rpc("book_seat", {"p_ride": ride_a, "p_pickup": offer_a["pickup_stop_id"], "p_dropoff": offer_a["dropoff_stop_id"]}), expect_error="already_booked")
    step("my_bookings mostra a reserva", lambda: require(any(b["id"] == booking_p1 for b in p1.rpc("my_bookings")), "reserva sumiu"))
    step("open_rides_overview", lambda: p1.rpc("open_rides_overview"))
    step("Motorista vê a passageira (my_rides.bookings)", lambda: require(any(b["id"] == booking_p1 for r in drv.rpc("my_rides") if r["id"] == ride_a for b in r["bookings"]), "não aparece"))

    # ------------------------------------------------- posição ao vivo / acompanhar
    start_pt = route["coordinates"][0]
    step("update_my_location (motorista com viagem saindo)", lambda: require(drv.rpc("update_my_location", {"p_lat": start_pt[1], "p_lng": start_pt[0], "p_heading": 90}) is True, "não guardou a posição"))
    step("nearby_drivers (passageira vê o carro dela)", lambda: require(any(d.get("is_my_ride") for d in p1.rpc("nearby_drivers", {"p_lat": start_pt[1], "p_lng": start_pt[0], "p_radius_m": 4000})), "carro não aparece"))
    step("track_ride (passageira acompanha)", lambda: require(p1.rpc("track_ride", {"p_ride": ride_a})["live"] is True, "sem posição ao vivo"))
    step("Estranho não acompanha a viagem", lambda: p2.rpc("track_ride", {"p_ride": ride_a}), expect_error="not_allowed")

    # ---------------------------------------------- cancelar, remover (viagem B)
    if ride_b:
        offer_b = step("Buscar a viagem B (passageiro)", lambda: find(p2, ride_b))
        if offer_b:
            args = {"p_ride": ride_b, "p_pickup": offer_b["pickup_stop_id"], "p_dropoff": offer_b["dropoff_stop_id"]}
            bk = step("Reservar na B", lambda: p2.rpc("book_seat", args))
            step("cancel_booking (passageiro desiste)", lambda: p2.rpc("cancel_booking", {"p_booking": bk}))
            bk2 = step("Reservar na B de novo", lambda: p2.rpc("book_seat", args))
            step("remove_passenger (motorista tira)", lambda: drv.rpc("remove_passenger", {"p_booking": bk2, "p_reason": "teste"}))
            step("Removido não reserva de novo", lambda: p2.rpc("book_seat", args), expect_error="removed_by_driver")
        step("cancel_ride (cancelar viagem B)", lambda: drv.rpc("cancel_ride", {"p_ride": ride_b}))

    # ------------------------------------------------------------- comunidades
    def community():
        drv.rpc("create_community", {"p_name": "QA Comunidade", "p_description": "teste automático", "p_kind": "group", "p_join_mode": "invite_code", "p_anchor_stop": None})
        c = [c for c in drv.rpc("my_communities") if c["name"] == "QA Comunidade"]
        require(c, "não aparece em my_communities")
        return c[0]
    com = step("create_community", community)
    if com:
        code = com.get("invite_code")
        step("join_community (passageira entra pelo código)", lambda: require(p1.rpc("join_community", {"p_invite_code": code}) == "active", "não ficou ativa"))
        step("community_members_list", lambda: require(len(drv.rpc("community_members_list", {"p_community": com["id"]})) == 2, "membros errados"))
        step("leave_community", lambda: p1.rpc("leave_community", {"p_community": com["id"]}))

    # ----------------------------------------------------------------- eventos
    start = (NOW + dt.timedelta(days=3)).replace(hour=22, minute=0, second=0, microsecond=0)  # 19h em Brasília
    step("similar_events", lambda: drv.rpc("similar_events", {"p_lat": STADIUM[0], "p_lng": STADIUM[1], "p_starts_at": iso(start)}))
    ev = step("CRIAR EVENTO (create_event)", lambda: drv.rpc("create_event", {
        "p_name": "QA Jogo", "p_kind": "esporte", "p_venue_label": "Estádio Mané Garrincha", "p_lat": STADIUM[0], "p_lng": STADIUM[1],
        "p_starts_at": iso(start), "p_ends_at": iso(start + dt.timedelta(hours=2)), "p_meeting_point": "Portão 3",
        "p_description": "teste automático", "p_community": None}))
    if ev:
        step("upcoming_events (passageira vê)", lambda: require(any(e["id"] == ev for e in p1.rpc("upcoming_events", {"p_lat": ASA_SUL_107[0], "p_lng": ASA_SUL_107[1]})), "evento não aparece"))
        evj = step("event_json", lambda: p1.rpc("event_json", {"p_event": ev, "p_lat": ASA_SUL_107[0], "p_lng": ASA_SUL_107[1]}))
        if evj:
            step("event_by_code", lambda: require(p1.rpc("event_by_code", {"p_code": evj["invite_code"]})["id"] == ev, "código não acha"))
        step("set_event_interest (preciso de carona)", lambda: p1.rpc("set_event_interest", {"p_event": ev, "p_leg": "ida", "p_lat": ASA_SUL_107[0], "p_lng": ASA_SUL_107[1], "p_on": True}))
        ev_route = step("Rota até o estádio (ORS)", lambda: ors_route(ASA_SUL_107, STADIUM))
        if ev_route:
            step("event_demand (motorista vê quem precisa)", lambda: require(drv.rpc("event_demand", {"p_event": ev, "p_leg": "ida", "p_route": ev_route}) >= 1, "não contou a passageira"))
            er = step("CARONA PARA O EVENTO (publish_event_ride ida)", lambda: drv.rpc("publish_event_ride", {
                "p_event": ev, "p_leg": "ida", "p_vehicle": car, "p_route": ev_route, "p_origin_label": "Asa Sul",
                "p_dest_label": "Estádio Mané Garrincha", "p_departure": iso(start - dt.timedelta(minutes=40)),
                "p_seats": 3, "p_women_only": False}))
            step("event_rides (passageira acha a carona)", lambda: require(any(o["ride"]["id"] == er["ride_id"] for o in p1.rpc("event_rides", {"p_event": ev, "p_leg": "ida", "p_lat": ASA_SUL_107[0], "p_lng": ASA_SUL_107[1]})), "não achou"))
            if er:
                step("Cancelar carona do evento", lambda: drv.rpc("cancel_ride", {"p_ride": er["ride_id"]}))
        step("cancel_event", lambda: drv.rpc("cancel_event", {"p_event": ev}))

    # ----------------------------------------------------------------- corrida
    if not booking_p1:
        return
    step("INICIAR CORRIDA (start_ride)", lambda: require(drv.rpc("start_ride", {"p_ride": ride_a})["status"] == "in_progress", "não começou"))
    step("Passageira não inicia corrida dos outros", lambda: p1.rpc("start_ride", {"p_ride": ride_a}), expect_error="not_allowed")
    step("update_my_location (corrida andando)", lambda: drv.rpc("update_my_location", {"p_lat": start_pt[1], "p_lng": start_pt[0], "p_heading": 90}))
    nav1 = step("NAVEGAÇÃO (driver_navigation)", lambda: drv.rpc("driver_navigation", {"p_ride": ride_a}))
    step("Navegação tem a parada da passageira", lambda: require(any(a["booking_id"] == booking_p1 and a["kind"] == "pickup" for s in nav1["stops"] for a in s["actions"]), "parada não está na lista"))

    if nav1 and nav1["stops"]:
        pts = [(start_pt[1], start_pt[0])] + [(s["lat"], s["lng"]) for s in nav1["stops"]] + [(nav1["destination"]["lat"], nav1["destination"]["lng"])]
        def nav_route():
            f = ors_nav(pts)
            steps_ = [s for seg in f["properties"]["segments"] for s in seg["steps"]]
            require(steps_ and steps_[0].get("instruction"), "sem instruções")
            return steps_[0]["instruction"]
        first = step("Rota de navegação com instruções em português (ORS)", nav_route)
        if first:
            print(f"   primeira instrução: {first}")

    # passageiro novo no caminho, com a corrida andando
    offer_live = step("Busca acha corrida já andando (parada à frente)", lambda: find(p2, ride_a, frm=(-15.8330, -47.9260), to=(-15.8495, -47.9480)))
    booking_p2 = None
    if offer_live:
        booking_p2 = step("Reservar com a corrida andando", lambda: p2.rpc("book_seat", {"p_ride": ride_a, "p_pickup": offer_live["pickup_stop_id"], "p_dropoff": offer_live["dropoff_stop_id"]}))
    nav2 = step("Navegação muda com o passageiro novo", lambda: drv.rpc("driver_navigation", {"p_ride": ride_a}))
    if nav1 and nav2:
        step("Versão da navegação mudou (app recalcula a rota)", lambda: require(nav2["version"] != nav1["version"], "versão igual"))
        step("Passageiro novo entrou na lista de paradas", lambda: require(any(a["booking_id"] == booking_p2 for s in nav2["stops"] for a in s["actions"]), "não entrou"))

    step("EMBARCOU (board_passenger)", lambda: drv.rpc("board_passenger", {"p_booking": booking_p1}))
    step("Passageira já embarcada não cancela", lambda: p1.rpc("cancel_booking", {"p_booking": booking_p1}), expect_error="cannot_cancel")
    if booking_p2:
        step("NÃO APARECEU (passenger_no_show)", lambda: drv.rpc("passenger_no_show", {"p_booking": booking_p2}))
    nav3 = step("Navegação só com o desembarque", lambda: drv.rpc("driver_navigation", {"p_ride": ride_a}))
    if nav3:
        step("Sobrou só deixar a passageira", lambda: require([a["kind"] for s in nav3["stops"] for a in s["actions"]] == ["dropoff"], f"ações: {[a['kind'] for s in nav3['stops'] for a in s['actions']]}"))
    step("DESEMBARCOU (drop_passenger)", lambda: drv.rpc("drop_passenger", {"p_booking": booking_p1}))
    step("ENCERRAR CORRIDA (finish_ride)", lambda: drv.rpc("finish_ride", {"p_ride": ride_a}))
    step("Reserva da passageira fica concluída", lambda: require([b["status"] for b in p1.rpc("my_bookings") if b["id"] == booking_p1] == ["completed"], "status errado"))
    step("stop_sharing_location", lambda: drv.rpc("stop_sharing_location"))


def report():
    ok = sum(1 for r in results if r[1])
    lines = [f"## Teste do Bora pela API: {ok}/{len(results)} etapas ok", "", "| | Etapa | ms | Detalhe |", "|---|---|---|---|"]
    for name, good, ms, detail in results:
        lines.append(f"| {'✅' if good else '❌'} | {name} | {ms} | {detail.replace('|', '/')} |")
    text = "\n".join(lines)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    slow = [r for r in results if r[2] > 4000 and r[1]]
    for name, _, ms, _ in slow:
        print(f"::warning::{name} demorou {ms} ms (a API corta em 8 s)")
    return ok == len(results)


if __name__ == "__main__":
    try:
        main()
    finally:
        sys.exit(0 if report() else 1)
