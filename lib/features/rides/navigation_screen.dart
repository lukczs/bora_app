import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import '../../core/widgets/measure_size.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../data/routing_service.dart';
import '../../domain/models.dart';

/// Corrida em andamento, do jeito do Waze/Uber: o mapa segue o carro, mostra a
/// próxima manobra e a próxima parada com quem pegar ou deixar.
///
/// A rota passa pelas paradas que ainda têm passageiro. Ela é recalculada
/// quando:
///  * entra um passageiro novo no caminho (ou alguém cancela/embarca);
///  * o motorista sai da rota.
class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key, required this.rideId});
  final String rideId;

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

const _dist = Distance();

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final _map = BoraMapController();
  final _tts = FlutterTts();

  NavPlan? _plan;
  NavRoute? _route;
  List<double> _cum = const []; // distância acumulada em cada ponto da rota
  final Map<String, int> _stopIndex = {}; // parada -> ponto da rota mais perto

  LatLng? _raw; // GPS
  LatLng? _shown; // posição desenhada (presa na rota quando perto dela)
  double _heading = 0;
  int _idx = 0; // segmento atual da rota
  double _along = 0; // metros andados na rota atual
  int _offCount = 0;

  bool _following = true;
  bool _muted = false;
  bool _rerouting = false;
  bool _busy = false;
  bool _gpsDenied = false;
  bool _closing = false; // encerrando/saindo: nada mais de GPS, timers ou voltas de tela
  String? _error;
  DateTime _lastReroute = DateTime(2000);
  double _panel = 260;
  final Set<String> _spoken = {};

  StreamSubscription<Position>? _gps;
  Timer? _poll;
  Timer? _presence;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _tts
      ..setLanguage('pt-BR')
      ..setSpeechRate(.5);
    _start();
  }

  void _stopEverything() {
    _closing = true;
    _autoTimer?.cancel();
    _gps?.cancel();
    _poll?.cancel();
    _presence?.cancel();
    _tts.stop();
  }

  /// Sai da navegação uma vez só (a corrida continua se não foi encerrada).
  void _leave() {
    if (_closing && !mounted) return;
    _stopEverything();
    if (mounted && context.canPop()) context.pop();
  }

  @override
  void dispose() {
    _gps?.cancel();
    _poll?.cancel();
    _presence?.cancel();
    _tts.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Começo
  // ------------------------------------------------------------------
  Future<void> _start() async {
    final store = ref.read(storeProvider);
    try {
      var plan = await store.driverNavigation(widget.rideId);
      if (plan.ride.status == RideStatus.open) {
        await store.startRide(widget.rideId);
        plan = await store.driverNavigation(widget.rideId);
      }
      if (!mounted) return;
      setState(() => _plan = plan);
      // Todas as paradas do caminho (não só as com passageiro) para desenhar no mapa
      store.ensureStops(plan.ride.path).then((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
      return;
    }

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _gpsDenied = true);
      } else {
        final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));
        _raw = _shown = LatLng(p.latitude, p.longitude);
      }
    } catch (_) {}
    _raw ??= _shown ??= store.position;

    await _reroute(force: true);
    _speak('start', _plan!.stops.isEmpty
        ? 'Corrida iniciada. Siga até ${_plan!.destinationLabel}.'
        : 'Corrida iniciada. Primeira parada: ${_plan!.stops.first.name}.');

    if (!_gpsDenied) {
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3),
      ).listen(_onFix, onError: (_) {});
    }
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refreshPlan());
    _presence = Timer.periodic(const Duration(seconds: 5), (_) {
      final p = _raw;
      if (p != null) store.reportLocation(p, _heading);
    });
    _follow();
  }

  // ------------------------------------------------------------------
  // Rota
  // ------------------------------------------------------------------
  Future<void> _reroute({bool force = false}) async {
    final plan = _plan, from = _raw;
    if (plan == null || from == null || _rerouting) return;
    if (!force && DateTime.now().difference(_lastReroute) < const Duration(seconds: 15)) return;
    _lastReroute = DateTime.now();
    setState(() => _rerouting = true);
    NavRoute route;
    try {
      route = await ref.read(routingProvider).navigate([
        from,
        for (final s in plan.stops) s.point,
        plan.destination,
      ]);
      _error = null;
    } catch (e) {
      // Sem instruções agora: mostra pelo menos a rota publicada.
      _error = 'Sem instruções de voz agora. Siga a linha verde.';
      route = NavRoute(points: plan.route, steps: const [], legEnds: const [], distanceM: plan.ride.distanceM, duration: Duration.zero);
    }
    if (!mounted) return;
    final cum = <double>[0];
    for (var i = 1; i < route.points.length; i++) {
      cum.add(cum.last + _dist.as(LengthUnit.Meter, route.points[i - 1], route.points[i]));
    }
    // Onde cada parada cai na rota (em ordem, sempre para a frente)
    _stopIndex.clear();
    var from0 = 0;
    for (final s in plan.stops) {
      var best = from0, bestD = double.infinity;
      for (var i = from0; i < route.points.length; i++) {
        final d = _dist.as(LengthUnit.Meter, route.points[i], s.point);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      _stopIndex[s.stopId] = best;
      from0 = best;
    }
    setState(() {
      _route = route;
      _cum = cum;
      _idx = 0;
      _along = 0;
      _offCount = 0;
      _rerouting = false;
      _spoken.removeWhere((k) => k.startsWith('step-'));
    });
    if (_raw != null) _snap(_raw!);
  }

  Future<void> _refreshPlan({bool force = false}) async {
    if (_closing) return;
    try {
      final plan = await ref.read(storeProvider).driverNavigation(widget.rideId);
      if (!mounted || _closing) return;
      if (plan.ride.status == RideStatus.completed || plan.ride.status == RideStatus.cancelled) {
        _leave();
        return;
      }
      final old = _plan;
      if (old != null && plan.version == old.version && !force) return;
      // Passageiro novo no caminho?
      final known = {for (final s in old?.stops ?? const <NavStop>[]) for (final a in s.actions) a.bookingId};
      for (final s in plan.stops) {
        for (final a in s.pickups) {
          if (old != null && !known.contains(a.bookingId)) {
            _speak('new-${a.bookingId}', 'Novo passageiro: ${a.name}, em ${s.name}. Rota atualizada.');
            if (mounted) showBoraError(context, 'Novo passageiro: ${a.name} em ${s.name}. Rota atualizada.');
          }
        }
      }
      setState(() => _plan = plan);
      final sameStops = old != null &&
          old.stops.length == plan.stops.length &&
          [for (var i = 0; i < plan.stops.length; i++) old.stops[i].stopId == plan.stops[i].stopId].every((x) => x);
      if (!sameStops) await _reroute(force: true);
    } catch (_) {
      // sem rede: tenta de novo no próximo ciclo
    }
  }

  // ------------------------------------------------------------------
  // GPS
  // ------------------------------------------------------------------
  void _onFix(Position p) {
    if (_closing) return;
    final here = LatLng(p.latitude, p.longitude);
    final moving = p.speed > 2;
    if (moving && p.heading >= 0) _heading = p.heading;
    _raw = here;
    _snap(here, gpsMoving: moving);
    _announce();
    _follow();
  }

  /// Prende a posição na rota, mede o quanto já andou e vê se saiu do caminho.
  void _snap(LatLng here, {bool gpsMoving = false}) {
    final pts = _route?.points ?? const <LatLng>[];
    if (pts.length < 2) {
      setState(() => _shown = here);
      return;
    }
    (int, LatLng, double) best = (_idx, pts[_idx], double.infinity);
    void search(int a, int b) {
      for (var i = math.max(0, a); i < math.min(pts.length - 1, b); i++) {
        final (q, d) = _project(here, pts[i], pts[i + 1]);
        if (d < best.$3) best = (i, q, d);
      }
    }

    search(_idx - 3, _idx + 120);
    if (best.$3 > 60) search(0, pts.length); // pulou? procura na rota toda
    final (i, q, d) = best;
    final off = d > 50;
    _offCount = off ? _offCount + 1 : 0;
    setState(() {
      _idx = i;
      _along = _cum[i] + _dist.as(LengthUnit.Meter, pts[i], q);
      _shown = d <= 30 ? q : here;
      if (!gpsMoving && d <= 30) _heading = _norm(_dist.bearing(pts[i], pts[i + 1]));
    });
    if (_offCount >= 3) {
      _speak('reroute-${DateTime.now().millisecondsSinceEpoch ~/ 20000}', 'Recalculando a rota.');
      _reroute();
    }
  }

  void _follow() {
    final p = _shown;
    if (!_following || p == null) return;
    // Olha um pouco à frente: o carro fica na parte de baixo da tela.
    final ahead = _dist.offset(p, 70, _heading);
    _map.follow(ahead, heading: _heading, zoom: 17);
  }

  // ------------------------------------------------------------------
  // Próxima manobra, próxima parada, voz
  // ------------------------------------------------------------------
  (NavStep?, double, int) _nextManeuver() {
    final r = _route;
    if (r == null || r.steps.isEmpty || _cum.isEmpty) return (null, 0, -1);
    var i = r.steps.indexWhere((s) => _idx >= s.from && _idx < s.to);
    if (i < 0) i = r.steps.length - 1;
    final n = math.min(i + 1, r.steps.length - 1);
    final next = r.steps[n];
    final at = next.from.clamp(0, _cum.length - 1);
    return (next, math.max(0.0, _cum[at] - _along), n);
  }

  String _stepText(NavStep s, int stepIndex) {
    if (s.type == 10) {
      // chegada de um trecho = uma parada (ou o destino)
      final stops = _plan?.stops ?? const <NavStop>[];
      for (final st in stops) {
        final idx = _stopIndex[st.stopId];
        if (idx != null && (idx - s.to).abs() <= 3) return 'Parada · ${st.name}';
      }
      return 'Chegada · ${_plan?.destinationLabel ?? 'destino'}';
    }
    return s.instruction;
  }

  double get _metersToNextStop {
    final s = _plan?.stops.firstOrNull;
    if (s == null || _cum.isEmpty) return double.infinity;
    final idx = _stopIndex[s.stopId];
    if (idx == null) return _dist.as(LengthUnit.Meter, _shown ?? s.point, s.point);
    return math.max(0.0, _cum[idx.clamp(0, _cum.length - 1)] - _along);
  }

  double get _metersToEnd => _cum.isEmpty ? 0 : math.max(0.0, _cum.last - _along);

  Duration get _timeToEnd {
    final r = _route;
    if (r == null || r.distanceM == 0 || r.duration == Duration.zero) {
      return Duration(seconds: (_metersToEnd / (30 / 3.6)).round());
    }
    return Duration(seconds: (r.duration.inSeconds * _metersToEnd / r.distanceM).round());
  }

  void _announce() {
    final (step, m, n) = _nextManeuver();
    if (step != null && step.type != 10) {
      final text = _stepText(step, n);
      if (m <= 400 && m > 150) _speak('step-$n-far', 'Em ${_roundM(m)} metros, $text');
      if (m <= 50) _speak('step-$n-now', text);
    }
    final stop = _plan?.stops.firstOrNull;
    if (stop != null && _metersToNextStop < 80) {
      final pick = stop.pickups.map((a) => a.name).join(' e ');
      final drop = stop.dropoffs.where((a) => a.status == BookingStatus.boarded).map((a) => a.name).join(' e ');
      _speak('arrive-${stop.stopId}', [
        'Você chegou em ${stop.name}.',
        if (drop.isNotEmpty) 'Deixe $drop.',
        if (pick.isNotEmpty) 'Pegue $pick.',
      ].join(' '));
    }
    _checkArrival();
  }

  // ------------------------------------------------------------------
  // Chegou no ponto final: encerra sozinha depois de uma contagem
  // ------------------------------------------------------------------
  static const _autoSeconds = 15;
  Timer? _autoTimer;
  int _autoLeft = 0;
  bool _autoDeclined = false; // motorista tocou "Ainda não"

  void _checkArrival() {
    final plan = _plan, here = _raw;
    if (plan == null || here == null || _closing) return;
    final toEnd = _dist.as(LengthUnit.Meter, here, plan.destination);
    // só falta coisa no próprio destino (ou nada)?
    final onlyAtEnd = plan.stops.every((s) => _dist.as(LengthUnit.Meter, s.point, plan.destination) < 150);
    final arrived = toEnd < 60 && onlyAtEnd;
    if (arrived && _autoTimer == null && !_autoDeclined) {
      _speak('end', 'Você chegou ao destino. A corrida vai ser encerrada em $_autoSeconds segundos.');
      setState(() => _autoLeft = _autoSeconds);
      _autoTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _closing) return t.cancel();
        setState(() => _autoLeft--);
        if (_autoLeft <= 0) {
          t.cancel();
          _finish(ask: false);
        }
      });
    } else if (toEnd > 150) {
      // saiu de perto do destino: cancela a contagem e volta a valer da próxima vez
      _cancelAuto();
      _autoDeclined = false;
    }
  }

  void _cancelAuto({bool declined = false}) {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (_autoLeft != 0 && mounted) setState(() => _autoLeft = 0);
    if (declined) _autoDeclined = true;
  }

  void _speak(String key, String text) {
    if (_spoken.contains(key)) return;
    _spoken.add(key);
    if (!_muted) _tts.speak(text);
  }

  // ------------------------------------------------------------------
  // Ações nas paradas
  // ------------------------------------------------------------------
  Future<void> _act(Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      await call();
      await _refreshPlan(force: true);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish({bool ask = true}) async {
    if (_closing) return;
    _cancelAuto();
    final plan = _plan;
    final onboard = [
      for (final s in plan?.stops ?? const <NavStop>[]) for (final a in s.dropoffs) if (a.status == BookingStatus.boarded) a.name
    ];
    final waiting = [for (final s in plan?.stops ?? const <NavStop>[]) for (final a in s.pickups) a.name];
    final ok = !ask ? true : await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Encerrar corrida?'),
        content: Text([
          if (onboard.isNotEmpty) '${onboard.join(', ')} ainda ${onboard.length == 1 ? 'está' : 'estão'} no carro e ${onboard.length == 1 ? 'vai' : 'vão'} ficar como entregue${onboard.length == 1 ? '' : 's'}.',
          if (waiting.isNotEmpty) '${waiting.join(', ')} ainda não ${waiting.length == 1 ? 'embarcou' : 'embarcaram'} e ${waiting.length == 1 ? 'fica' : 'ficam'} como "não apareceu".',
          if (onboard.isEmpty && waiting.isEmpty) 'Todo mundo já desceu. Bom trabalho!',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Continuar')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Encerrar', style: TextStyle(color: AppColors.green))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    // Para GPS e consultas antes: senão uma consulta atrasada vê a corrida
    // encerrada e fecha a tela de novo (era o "sai e volta sozinho").
    _stopEverything();
    try {
      await ref.read(storeProvider).finishRide(widget.rideId);
      if (!mounted) return;
      showBoraError(context, 'Corrida encerrada. Obrigado por levar a galera!');
      if (context.canPop()) context.pop();
    } catch (e) {
      // não encerrou: volta a acompanhar
      _closing = false;
      if (mounted) {
        showBoraError(context, friendlyError(e));
        _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refreshPlan());
        _presence = Timer.periodic(const Duration(seconds: 5), (_) {
          final p = _raw;
          if (p != null) ref.read(storeProvider).reportLocation(p, _heading);
        });
        if (!_gpsDenied) {
          _gps = Geolocator.getPositionStream(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3),
          ).listen(_onFix, onError: (_) {});
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------
  // Tela
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final top = MediaQuery.paddingOf(context).top;
    if (plan == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(Space.page),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: AppText.body, textAlign: TextAlign.center),
                    const SizedBox(height: Space.md),
                    BoraButton(label: 'Voltar', expand: false, onPressed: () => context.pop()),
                  ]),
                ),
        ),
      );
    }

    final (step, meters, stepIndex) = _nextManeuver();
    final route = _route?.points ?? plan.route;
    final ahead = _idx < route.length ? route.sublist(_idx) : route;
    final store = ref.read(storeProvider);
    final pending = {for (final s in plan.stops) s.stopId};
    final pins = <MapPin>[
      // todas as paradas do caminho (as com passageiro vêm destacadas abaixo)
      for (final id in plan.ride.path)
        if (!pending.contains(id) && !id.startsWith('r_')) stopPin('route-$id', store.stop(id).point),
      for (final s in plan.stops)
        highlightPin('nav-${s.stopId}', s.point, _stopLabel(s)),
      destinationPin(plan.destination),
      if (_shown != null) carPin('me', _shown!, heading: _heading, mine: true),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) {
              if (_following) setState(() => _following = false);
            },
            child: BoraMap(
              controller: _map,
              center: _shown ?? plan.destination,
              zoom: 16,
              pins: pins,
              lines: [routeLine('nav', ahead.length > 1 ? ahead : route)],
              padding: EdgeInsets.only(top: top + 120, bottom: _panel),
            ),
          ),

          // Próxima manobra
          Positioned(
            top: top + Space.xs,
            left: Space.sm,
            right: Space.sm,
            child: _ManeuverBanner(
              step: step,
              text: step == null ? null : _stepText(step, stepIndex),
              meters: meters,
              rerouting: _rerouting,
              note: _gpsDenied ? 'Sem permissão de localização: a rota não acompanha o carro.' : _error,
              onClose: _leave,
            ),
          ),

          // Botões laterais
          Positioned(
            right: Space.md,
            bottom: _panel + Space.sm,
            child: Column(children: [
              RoundIconButton(
                icon: _muted ? Icons.volume_off : Icons.volume_up,
                tooltip: _muted ? 'Ligar a voz' : 'Desligar a voz',
                onPressed: () {
                  setState(() => _muted = !_muted);
                  if (_muted) _tts.stop();
                },
              ),
              const SizedBox(height: Space.xs),
              RoundIconButton(
                icon: Icons.alt_route,
                tooltip: 'Ver a rota inteira',
                onPressed: () {
                  setState(() => _following = false);
                  _map.resetBearing();
                  _map.fit([if (_shown != null) _shown!, ...plan.stops.map((s) => s.point), plan.destination]);
                },
              ),
            ]),
          ),
          if (!_following)
            Positioned(
              left: Space.md,
              bottom: _panel + Space.sm,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.surfaceRaised, foregroundColor: AppColors.text),
                onPressed: () {
                  setState(() => _following = true);
                  _follow();
                },
                icon: const Icon(Icons.navigation),
                label: const Text('Voltar à rota'),
              ),
            ),

          // Painel de baixo
          Align(
            alignment: Alignment.bottomCenter,
            child: MeasureSize(
              onChange: (sz) {
                if ((sz.height - _panel).abs() > 4) setState(() => _panel = sz.height);
              },
              child: _NavPanel(
                plan: plan,
                metersToStop: _metersToNextStop,
                metersToEnd: _metersToEnd,
                timeToEnd: _timeToEnd,
                busy: _busy,
                onBoard: (a) => _act(() => ref.read(storeProvider).boardPassenger(a.bookingId)),
                onNoShow: (a) => _act(() => ref.read(storeProvider).passengerNoShow(a.bookingId)),
                onDrop: (a) => _act(() => ref.read(storeProvider).dropPassenger(a.bookingId)),
                onFinish: _finish,
                autoLeft: _autoLeft,
                onKeepGoing: () => _cancelAuto(declined: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stopLabel(NavStop s) {
    final pick = s.pickups.map((a) => a.name).toList();
    final drop = s.dropoffs.where((a) => a.status == BookingStatus.boarded).map((a) => a.name).toList();
    return [
      if (pick.isNotEmpty) 'Pegar ${pick.join(', ')}',
      if (drop.isNotEmpty) 'Deixar ${drop.join(', ')}',
    ].join(' · ').ifEmpty(s.name);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

double _norm(double deg) => (deg % 360 + 360) % 360;

int _roundM(double m) => m >= 100 ? (m / 50).round() * 50 : (m / 10).round() * 10;

String _fmtDist(double m) {
  if (m.isInfinite) return '';
  if (m < 1000) return '${_roundM(m)} m';
  return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Projeta [p] no segmento a-b. Devolve o ponto e a distância em metros.
(LatLng, double) _project(LatLng p, LatLng a, LatLng b) {
  final k = math.cos(p.latitude * math.pi / 180);
  final ax = a.longitude * k, ay = a.latitude, bx = b.longitude * k, by = b.latitude;
  final px = p.longitude * k, py = p.latitude;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final q = LatLng(ay + t * dy, (ax + t * dx) / k);
  return (q, _dist.as(LengthUnit.Meter, p, q));
}

IconData _maneuverIcon(int type) => switch (type) {
      0 => Icons.turn_left,
      1 => Icons.turn_right,
      2 => Icons.turn_sharp_left,
      3 => Icons.turn_sharp_right,
      4 => Icons.turn_slight_left,
      5 => Icons.turn_slight_right,
      7 || 8 => Icons.roundabout_right,
      9 => Icons.u_turn_left,
      10 => Icons.flag,
      12 => Icons.fork_left,
      13 => Icons.fork_right,
      _ => Icons.straight,
    };

class _ManeuverBanner extends StatelessWidget {
  const _ManeuverBanner({
    required this.step,
    required this.text,
    required this.meters,
    required this.rerouting,
    required this.note,
    required this.onClose,
  });
  final NavStep? step;
  final String? text;
  final double meters;
  final bool rerouting;
  final String? note;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, Space.sm),
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: Shadows.floating,
          ),
          child: Row(
            children: [
              Icon(rerouting ? Icons.sync : _maneuverIcon(step?.type ?? 6), size: 44, color: AppColors.night),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rerouting ? 'Recalculando…' : (step == null ? 'Siga a rota' : _fmtDist(meters)),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night, height: 1.1),
                    ),
                    if (!rerouting && text != null)
                      Text(text!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.night, height: 1.25)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sair da navegação',
                onPressed: onClose,
                icon: const Icon(Icons.close, color: AppColors.night),
              ),
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: Space.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text(note!, style: AppText.caption.copyWith(color: AppColors.warning)),
          ),
        ],
      ],
    );
  }
}

class _NavPanel extends StatelessWidget {
  const _NavPanel({
    required this.plan,
    required this.metersToStop,
    required this.metersToEnd,
    required this.timeToEnd,
    required this.busy,
    required this.onBoard,
    required this.onNoShow,
    required this.onDrop,
    required this.onFinish,
    this.autoLeft = 0,
    this.onKeepGoing,
  });
  final int autoLeft;
  final VoidCallback? onKeepGoing;
  final NavPlan plan;
  final double metersToStop;
  final double metersToEnd;
  final Duration timeToEnd;
  final bool busy;
  final void Function(NavAction) onBoard;
  final void Function(NavAction) onNoShow;
  final void Function(NavAction) onDrop;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final next = plan.stops.firstOrNull;
    final arrived = next != null && metersToStop < 120;
    final atEnd = next == null && metersToEnd < 300;
    final eta = DateTime.now().add(timeToEnd);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.md + bottom),
      decoration: const BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        boxShadow: Shadows.floating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (autoLeft > 0) ...[
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(Radii.md)),
              child: Row(children: [
                const Icon(Icons.flag, color: AppColors.night),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text('Você chegou! Encerrando a corrida em $autoLeft s',
                      style: const TextStyle(color: AppColors.night, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: onKeepGoing,
                  child: const Text('Ainda não', style: TextStyle(color: AppColors.night, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            const SizedBox(height: Space.sm),
          ],
          // Chegada no destino final
          Row(children: [
            Text(formatTime(eta), style: AppText.title.copyWith(color: AppColors.green)),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text('${timeToEnd.inMinutes} min · ${_fmtDist(metersToEnd)} até ${plan.destinationLabel}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label),
            ),
          ]),
          const Divider(height: Space.lg),
          if (next != null) ...[
            Text(arrived ? 'Você chegou' : 'Próxima parada · ${_fmtDist(metersToStop)}',
                style: AppText.overline.copyWith(color: arrived ? AppColors.green : AppColors.textFaint)),
            const SizedBox(height: 2),
            Text(next.name, style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.xs),
            for (final a in next.dropoffs.where((a) => a.status == BookingStatus.boarded))
              _ActionRow(
                action: a,
                text: 'Deixar ${a.name}',
                icon: Icons.logout,
                primary: ('Desceu', () => onDrop(a)),
                busy: busy,
              ),
            for (final a in next.pickups)
              _ActionRow(
                action: a,
                text: a.byCar ? 'Pegar ${a.name} (vem até o carro)' : 'Pegar ${a.name}',
                icon: Icons.login,
                primary: ('Embarcou', () => onBoard(a)),
                secondary: ('Não veio', () => onNoShow(a)),
                busy: busy,
              ),
            if (plan.stops.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: Space.xxs),
                child: Text('Depois: ${plan.stops.skip(1).map((s) => s.name).take(2).join(', ')}'
                    '${plan.stops.length > 3 ? ' e mais ${plan.stops.length - 3}' : ''}',
                    style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: Space.sm),
            BoraButton(label: 'Encerrar corrida', kind: BoraButtonKind.ghost, compact: true, onPressed: busy ? null : onFinish),
          ] else ...[
            Text(atEnd ? 'Você chegou ao destino' : 'Ninguém mais para pegar ou deixar',
                style: AppText.overline.copyWith(color: atEnd ? AppColors.green : AppColors.textFaint)),
            const SizedBox(height: 2),
            Text(plan.destinationLabel, style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.sm),
            BoraButton(
              label: 'Encerrar corrida',
              icon: Icons.flag,
              kind: atEnd ? BoraButtonKind.primary : BoraButtonKind.secondary,
              loading: busy,
              onPressed: onFinish,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.text, required this.icon, required this.primary, required this.busy, this.secondary});
  final NavAction action;
  final String text;
  final IconData icon;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.green),
          const SizedBox(width: Space.xs),
          Expanded(child: Text(text, style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (secondary != null)
            TextButton(onPressed: busy ? null : secondary!.$2, child: Text(secondary!.$1, style: const TextStyle(color: AppColors.textMuted))),
          const SizedBox(width: Space.xxs),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: AppColors.night),
            onPressed: busy ? null : primary.$2,
            child: Text(primary.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
