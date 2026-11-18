import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/measure_size.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/bora_store.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';
import '../places/place_picker.dart';

/// Etapas da carona, sempre num bottom sheet sobre o mapa (padrão Uber).
enum _Stage { idle, results, offer, tracking }

class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});
  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> {
  final _map = BoraMapController();
  _Stage _stage = _Stage.idle;

  // Camadas dinâmicas
  static const _stopsMinZoom = 15.0; // paradas só aparecem de perto (estilo Moovit)
  List<Stop> _visibleStops = const [];
  List<NearbyDriver> _drivers = const [];
  Timer? _cameraDebounce;
  Timer? _driversTimer;
  Timer? _trackTimer;
  MapView? _camera;
  double _sheetHeight = 200;
  static const _namesMinZoom = 16.5; // nomes das paradas aparecem bem de perto

  // Fluxo
  Place? _origin;
  Place? _destination;
  List<RideOffer> _offers = const [];
  RideOffer? _selected;
  List<LatLng> _selectedRoute = const [];
  bool _busy = false;
  Booking? _trackingBooking;
  RideTracking? _tracking;
  List<LatLng> _trackingRoute = const [];

  @override
  void initState() {
    super.initState();
    _driversTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadDrivers());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDrivers());
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    _driversTimer?.cancel();
    _trackTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Camadas
  // ------------------------------------------------------------------
  bool _zoomedIn = false;

  bool _showNames = false;

  void _onMove(MapView v) {
    final zoomed = v.zoom >= _stopsMinZoom;
    final names = v.zoom >= _namesMinZoom;
    if (zoomed != _zoomedIn || names != _showNames) {
      setState(() {
        _zoomedIn = zoomed;
        _showNames = names;
      });
    }
  }

  void _onIdle(MapView v) {
    _camera = v;
    _onMove(v);
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 200), _loadStops);
  }

  Future<void> _loadStops() async {
    final cam = _camera;
    if (cam == null || cam.bounds == null || !mounted) return;
    if (cam.zoom < _stopsMinZoom) {
      if (_visibleStops.isNotEmpty) setState(() => _visibleStops = const []);
      return;
    }
    try {
      final stops = await ref.read(storeProvider).stopsInView(cam.bounds!);
      if (mounted) setState(() => _visibleStops = stops);
    } catch (_) {}
  }

  Future<void> _loadDrivers() async {
    if (!mounted || _stage == _Stage.tracking) return;
    try {
      final center = _camera?.center ?? ref.read(storeProvider).position;
      final d = await ref.read(storeProvider).nearbyDrivers(center);
      if (mounted) setState(() => _drivers = d);
    } catch (_) {}
  }

  Future<void> _centerOnMe() async {
    final store = ref.read(storeProvider);
    final real = await store.locate(askPermission: true);
    if (!mounted) return;
    await _map.moveTo(store.position, zoom: 15.5);
    if (!mounted) return;
    if (!real) showBoraError(context, 'Sem acesso ao GPS. Usando a Rodoviária do Plano como referência.');
  }

  void _fit(List<LatLng> pts) {
    if (pts.length < 2) return;
    // Espera o painel de baixo assumir a altura nova antes de enquadrar.
    Future<void>.delayed(const Duration(milliseconds: 280), () => _map.fit(pts));
  }

  // ------------------------------------------------------------------
  // Fluxo do passageiro
  // ------------------------------------------------------------------
  Future<void> _chooseDestination({bool onMap = false}) async {
    final store = ref.read(storeProvider);
    final p = onMap
        ? await MapPickerScreen.open(context, title: 'Para onde vamos?', start: _camera?.center)
        : await PlaceSearchScreen.open(context);
    if (p == null || !mounted) return;
    _origin ??= Place(label: 'Minha localização', point: store.position);
    _destination = p;
    await _search();
  }

  Future<void> _changeOrigin() async {
    final p = await PlaceSearchScreen.open(context, title: 'De onde você sai?', hint: 'Buscar ponto de partida', allowMyLocation: true);
    if (p == null || !mounted) return;
    _origin = p;
    if (_destination != null) await _search();
  }

  Future<void> _search() async {
    final from = _origin, to = _destination;
    if (from == null || to == null) return;
    setState(() {
      _busy = true;
      _stage = _Stage.results;
      _selected = null;
      _selectedRoute = const [];
    });
    _fit([from.point, to.point]);
    try {
      final offers = await ref.read(storeProvider).searchNear(from: from.point, to: to.point);
      if (mounted) setState(() => _offers = offers);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(RideOffer o) async {
    setState(() {
      _selected = o;
      _stage = _Stage.offer;
    });
    try {
      final route = await ref.read(storeProvider).rideRoute(o.ride.id);
      if (!mounted) return;
      setState(() => _selectedRoute = route);
      _fit([
        if (_origin != null) _origin!.point,
        if (o.pickup != null) o.pickup!.point,
        if (o.dropoff != null) o.dropoff!.point,
        if (_destination != null) _destination!.point,
      ]);
    } catch (_) {}
  }

  Future<void> _book() async {
    final o = _selected;
    if (o == null) return;
    setState(() => _busy = true);
    try {
      final store = ref.read(storeProvider);
      final id = await store.bookSeat(rideId: o.ride.id, pickupStopId: o.pickupStopId, dropoffStopId: o.dropoffStopId);
      final booking = store.myBooking(id);
      if (!mounted) return;
      if (booking != null) _startTracking(booking);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    _trackTimer?.cancel();
    setState(() {
      _stage = _Stage.idle;
      _destination = null;
      _origin = null;
      _offers = const [];
      _selected = null;
      _selectedRoute = const [];
      _trackingBooking = null;
      _tracking = null;
      _trackingRoute = const [];
    });
    _loadDrivers();
  }

  // ------------------------------------------------------------------
  // Acompanhar
  // ------------------------------------------------------------------
  Future<void> _startTracking(Booking b) async {
    _trackTimer?.cancel();
    setState(() {
      _trackingBooking = b;
      _stage = _Stage.tracking;
      _drivers = const [];
    });
    try {
      final route = await ref.read(storeProvider).rideRoute(b.rideId);
      if (mounted) setState(() => _trackingRoute = route);
      final pickup = ref.read(storeProvider).stop(b.pickupStopId).point;
      _fit([pickup, ...route.take(1)]);
    } catch (_) {}
    await _poll();
    _trackTimer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  Future<void> _poll() async {
    final b = _trackingBooking;
    if (b == null) return;
    try {
      final t = await ref.read(storeProvider).trackRide(b.rideId);
      if (mounted) setState(() => _tracking = t);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final upcoming = store.myBookings
        .where((b) => (b.status == BookingStatus.reserved || b.status == BookingStatus.boarded) && b.ride != null)
        .toList()
      ..sort((a, b) => a.ride!.departureAt.compareTo(b.ride!.departureAt));

    final pins = <MapPin>[
      if (_stage == _Stage.idle)
        for (final s in _visibleStops)
          stopPin(s.id, s.point, name: _showNames ? s.name : null, onTap: () => _showStop(s)),
      if (_stage != _Stage.tracking)
        for (final d in _drivers) carPin(d.rideId, d.point, heading: d.heading, mine: d.isMyRide),
      youPin(store.position),
      if (_origin != null && _stage != _Stage.idle && _origin!.label != 'Minha localização') originPin(_origin!.point),
      if (_destination != null && _stage != _Stage.idle) destinationPin(_destination!.point),
      if (_selected?.pickup != null)
        highlightPin('pickup', _selected!.pickup!.point,
            _selected!.pickupByCar ? 'Carro aqui · ${formatTime(_selected!.pickupEta ?? _selected!.ride.departureAt)}' : 'Embarque · ${_selected!.pickup!.name}'),
      if (_selected?.dropoff != null) highlightPin('dropoff', _selected!.dropoff!.point, 'Desembarque · ${_selected!.dropoff!.name}'),
      if (_stage == _Stage.tracking && _trackingBooking != null)
        highlightPin('my-pickup', store.stop(_trackingBooking!.pickupStopId).point,
            _trackingBooking!.pickupByCar ? 'Carro aqui' : 'Seu embarque · ${store.stop(_trackingBooking!.pickupStopId).name}'),
      if (_stage == _Stage.tracking && _tracking?.driverPoint != null)
        carPin('tracked', _tracking!.driverPoint!, heading: _tracking!.heading, mine: true),
    ];

    final lines = <MapLine>[
      if (_selectedRoute.isNotEmpty) routeLine('selected', _selectedRoute),
      if (_trackingRoute.isNotEmpty) routeLine('tracking', _trackingRoute),
    ];

    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          BoraMap(
            controller: _map,
            center: store.position,
            zoom: 14,
            pins: pins,
            lines: lines,
            padding: EdgeInsets.only(top: top + 64, bottom: _sheetHeight),
            onMove: _onMove,
            onIdle: _onIdle,
          ),
          // Topo
          Positioned(
            top: MediaQuery.paddingOf(context).top + Space.sm,
            left: Space.md,
            right: Space.md,
            child: Row(
              children: [
                if (_stage != _Stage.idle)
                  RoundIconButton(
                    icon: Icons.arrow_back,
                    onPressed: () {
                      if (_stage == _Stage.offer) {
                        setState(() {
                          _stage = _Stage.results;
                          _selected = null;
                          _selectedRoute = const [];
                        });
                      } else {
                        _reset();
                      }
                    },
                  )
                else
                  _TopChip(
                    text: store.me?.firstName.isNotEmpty == true ? 'Olá, ${store.me!.firstName}' : 'Bora',
                    sub: store.activeDriverRide != null ? 'Compartilhando localização' : null,
                  ),
                const Spacer(),
              ],
            ),
          ),
          // Botão "minha localização" logo acima do painel (posição padrão de app de mapa)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            right: Space.md,
            bottom: _sheetHeight + Space.sm,
            child: RoundIconButton(icon: Icons.my_location, tooltip: 'Minha localização', onPressed: _centerOnMe),
          ),
          if (_stage == _Stage.idle && !_zoomedIn)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 72,
              left: 0,
              right: 0,
              child: const Center(child: _Hint('Aproxime o mapa para ver as paradas')),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: MeasureSize(
              onChange: (sz) {
                if ((sz.height - _sheetHeight).abs() > 4) setState(() => _sheetHeight = sz.height);
              },
              child: _sheet(store, upcoming),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheet(BoraStore store, List<Booking> upcoming) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (c, a) => SlideTransition(
          position: Tween(begin: const Offset(0, .08), end: Offset.zero).animate(a), child: FadeTransition(opacity: a, child: c)),
      child: switch (_stage) {
        _Stage.idle => _IdleSheet(
            key: const ValueKey('idle'),
            upcoming: upcoming.isEmpty ? null : upcoming.first,
            stopName: upcoming.isEmpty ? null : store.stop(upcoming.first.pickupStopId).name,
            onWhereTo: () => _chooseDestination(),
            onPickOnMap: () => _chooseDestination(onMap: true),
            onTrack: upcoming.isEmpty ? null : () => _startTracking(upcoming.first),
            onOffer: () => context.push(store.myVehicles.isEmpty ? '/vehicle' : '/publish'),
            activeRide: store.activeDriverRide,
          ),
        _Stage.results => _ResultsSheet(
            key: const ValueKey('results'),
            origin: _origin,
            destination: _destination,
            offers: _offers,
            loading: _busy,
            onChangeOrigin: _changeOrigin,
            onChangeDestination: () => _chooseDestination(),
            onSelect: _select,
          ),
        _Stage.offer => _OfferSheet(key: const ValueKey('offer'), offer: _selected!, loading: _busy, onBook: _book),
        _Stage.tracking => _TrackingSheet(
            key: const ValueKey('tracking'),
            booking: store.myBooking(_trackingBooking!.id) ?? _trackingBooking!,
            tracking: _tracking,
            pickupName: store.stop(_trackingBooking!.pickupStopId).name,
            onClose: _reset,
            onDetails: () => context.push('/booking/${_trackingBooking!.id}'),
          ),
      },
    );
  }

  void _showStop(Stop stop) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stop.name, style: AppText.title),
            if (stop.region.isNotEmpty) Text(stop.region, style: AppText.caption),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.xs, children: [
              const Pill('Parada de ônibus', icon: Icons.directions_bus_outlined),
              if (stop.hasShelter == true) const Pill('Coberta', icon: Icons.roofing, color: AppColors.textMuted),
              if (stop.isLit == true) const Pill('Iluminada', icon: Icons.light_mode_outlined, color: AppColors.warning),
            ]),
            const SizedBox(height: Space.lg),
            BoraButton(
              label: 'Sair daqui',
              icon: Icons.arrow_upward,
              onPressed: () {
                Navigator.of(sheet).pop();
                _origin = Place(label: stop.name, point: stop.point);
                _chooseDestination();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Peças do sheet
// ======================================================================
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.maxHeightFactor = .62});
  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor),
      decoration: const BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        boxShadow: Shadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: Space.xs, bottom: Space.xs),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _IdleSheet extends StatelessWidget {
  const _IdleSheet({
    super.key,
    required this.onWhereTo,
    required this.onPickOnMap,
    required this.onOffer,
    this.upcoming,
    this.stopName,
    this.onTrack,
    this.activeRide,
  });
  final VoidCallback onWhereTo;
  final VoidCallback onPickOnMap;
  final VoidCallback onOffer;
  final Booking? upcoming;
  final String? stopName;
  final VoidCallback? onTrack;
  final Ride? activeRide;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (upcoming != null) ...[
              BoraCard(
                onTap: onTrack,
                highlight: true,
                child: Row(
                  children: [
                    const IconTile(Icons.directions_car_filled, color: AppColors.night, background: AppColors.green),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sua carona · ${formatWhen(upcoming!.ride!.departureAt)}', style: AppText.bodyStrong),
                          Text('Embarque em ${stopName ?? 'parada'}', style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const Text('Acompanhar', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
            ],
            // "Para onde vamos?"
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: onWhereTo,
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  child: const Row(
                    children: [
                      Icon(Icons.search, color: AppColors.text),
                      SizedBox(width: Space.sm),
                      Expanded(child: Text('Para onde vamos?', style: AppText.title)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(icon: Icons.push_pin_outlined, label: 'Escolher no mapa', onTap: onPickOnMap),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: _QuickAction(
                    icon: activeRide != null ? Icons.navigation_outlined : Icons.add_road,
                    label: activeRide != null ? 'Minha viagem' : 'Oferecer carona',
                    onTap: activeRide != null ? () => context.push('/my-ride/${activeRide!.id}') : onOffer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.text),
                const SizedBox(width: Space.xs),
                Flexible(child: Text(label, style: AppText.label.copyWith(color: AppColors.text), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      );
}

class _ResultsSheet extends StatelessWidget {
  const _ResultsSheet({
    super.key,
    required this.origin,
    required this.destination,
    required this.offers,
    required this.loading,
    required this.onChangeOrigin,
    required this.onChangeDestination,
    required this.onSelect,
  });
  final Place? origin;
  final Place? destination;
  final List<RideOffer> offers;
  final bool loading;
  final VoidCallback onChangeOrigin;
  final VoidCallback onChangeDestination;
  final ValueChanged<RideOffer> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
        children: [
          BoraCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Editable(text: origin?.label ?? 'Minha localização', onTap: onChangeOrigin),
                      const Divider(height: Space.md),
                      _Editable(text: destination?.label ?? '', onTap: onChangeDestination, strong: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (offers.isEmpty)
            const EmptyState(
              icon: Icons.route_outlined,
              title: 'Nenhuma carona nesse caminho agora',
              text: 'Guardamos sua busca: motoristas que fazem esse trajeto vão ver que tem gente precisando.',
            )
          else ...[
            Text('${offers.length} ${offers.length == 1 ? 'carona encontrada' : 'caronas encontradas'}', style: AppText.label),
            const SizedBox(height: Space.xs),
            for (final (i, o) in offers.indexed) ...[
              _OfferTile(offer: o, best: i == 0, onTap: () => onSelect(o)),
              const SizedBox(height: Space.xs),
            ],
          ],
        ],
      ),
    );
  }
}

class _Editable extends StatelessWidget {
  const _Editable({required this.text, required this.onTap, this.strong = false});
  final String text;
  final VoidCallback onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: strong ? AppColors.green : AppColors.text,
                  shape: strong ? BoxShape.rectangle : BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: strong ? AppText.bodyStrong : AppText.body),
              ),
              const Icon(Icons.edit_outlined, size: 16, color: AppColors.textFaint),
            ],
          ),
        ),
      );
}

String _minutesUntil(DateTime t) {
  final m = t.difference(DateTime.now()).inMinutes;
  if (m <= 1) return 'agora';
  if (m < 60) return '$m min';
  return formatTime(t);
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.onTap, this.best = false});
  final RideOffer offer;
  final VoidCallback onTap;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final r = offer.ride;
    return BoraCard(
      onTap: onTap,
      highlight: best,
      child: Row(
        children: [
          Avatar(r.driver.initial),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text('${r.driver.firstName} · ${r.vehicle.model}', style: AppText.bodyStrong, overflow: TextOverflow.ellipsis)),
                  if (best) ...[const SizedBox(width: Space.xs), const Pill('Melhor opção')],
                ]),
                const SizedBox(height: 2),
                const SizedBox(height: 2),
                _ModeLine(offer: offer),
                Text(
                  '${r.seatsAvailable} ${r.seatsAvailable == 1 ? 'vaga' : 'vagas'}',
                  style: AppText.caption,
                ),
                if (offer.sharedCommunities.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Pill(offer.sharedCommunities.first, icon: Icons.groups_outlined, color: AppColors.mint),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Metric(
            value: formatCents(offer.priceCents),
            label: offer.pickupEta == null ? '' : _minutesUntil(offer.pickupEta!),
            alignEnd: true,
          ),
        ],
      ),
    );
  }
}

class _OfferSheet extends StatelessWidget {
  const _OfferSheet({super.key, required this.offer, required this.loading, required this.onBook});
  final RideOffer offer;
  final bool loading;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final r = offer.ride;
    return _SheetFrame(
      maxHeightFactor: .7,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
        children: [
          Row(
            children: [
              Expanded(child: Text('Confirmar carona', style: AppText.headline.copyWith(fontSize: 22))),
              Metric(value: formatCents(offer.priceCents), label: 'rateio sugerido', alignEnd: true),
            ],
          ),
          const SizedBox(height: Space.md),
          _PickupPlan(offer: offer),
          const SizedBox(height: Space.md),
          RouteSummary(
            from: offer.pickupByCar ? 'Carro na saída · ${offer.ride.originLabel ?? offer.pickup?.name ?? ''}' : (offer.pickup?.name ?? 'Embarque'),
            fromDetail: [
              if (offer.pickupEta != null) (offer.pickupByCar ? 'Sai às ' : 'Carro passa às ') + formatTime(offer.pickupEta!),
              if (offer.pickupWalkM != null) '${offer.pickupWalkM} m a pé de você',
            ].join(' · '),
            to: offer.dropoff?.name ?? 'Desembarque',
            toDetail: [
              if (offer.dropoffEta != null) 'Chegada por volta das ${formatTime(offer.dropoffEta!)}',
              if (offer.dropoffWalkM != null) '${offer.dropoffWalkM} m até o destino',
            ].join(' · '),
          ),
          const SizedBox(height: Space.md),
          const Divider(),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Avatar(r.driver.initial),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.driver.firstName, style: AppText.bodyStrong),
                    Text('${r.vehicle.brand} ${r.vehicle.model} · ${r.vehicle.color}', style: AppText.caption),
                  ],
                ),
              ),
              Row(children: [
                const Icon(Icons.star_rounded, size: 18, color: AppColors.warning),
                const SizedBox(width: 2),
                Text(r.driver.ratingLabel, style: AppText.label.copyWith(color: AppColors.text)),
              ]),
            ],
          ),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
            const Pill('Identidade verificada', icon: Icons.verified_user_outlined),
            if (r.womenOnly) const Pill('Só mulheres', icon: Icons.female, color: AppColors.mint),
            for (final c in offer.sharedCommunities) Pill(c, icon: Icons.groups_outlined, color: AppColors.mint),
          ]),
          const SizedBox(height: Space.md),
          const Text(
            'A placa e o nome completo aparecem depois da reserva. O valor é um rateio de custo, pago direto ao motorista.',
            style: AppText.caption,
          ),
          const SizedBox(height: Space.md),
          BoraButton(label: 'Reservar vaga', loading: loading, onPressed: onBook),
        ],
      ),
    );
  }
}

class _TrackingSheet extends StatelessWidget {
  const _TrackingSheet({super.key, required this.booking, required this.tracking, required this.pickupName, required this.onClose, required this.onDetails});
  final Booking booking;
  final RideTracking? tracking;
  final String pickupName;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final r = booking.ride;
    final t = tracking;
    final eta = t?.pickupEta;
    final headline = eta == null
        ? 'Carona reservada'
        : (t!.live ? 'Motorista chega em ${_minutesUntil(eta)}' : 'Saída às ${formatTime(r?.departureAt ?? eta)}');

    return _SheetFrame(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
        children: [
          Text(headline, style: AppText.headline.copyWith(fontSize: 22)),
          const SizedBox(height: 2),
          Text(
            t?.live == true
                ? 'Posição atualizada em tempo real · embarque em $pickupName'
                : 'O carro aparece no mapa quando o motorista sair. Embarque em $pickupName.',
            style: AppText.body,
          ),
          const SizedBox(height: Space.md),
          if (booking.beThereBy != null)
            BoraCard(
              highlight: true,
              child: Row(children: [
                Icon(booking.pickupByCar ? Icons.directions_walk : Icons.directions_bus_outlined, color: AppColors.green),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    booking.pickupByCar
                        ? 'Vá até o carro na saída. Esteja lá até ${formatTime(booking.beThereBy!)}.'
                        : 'Esteja em $pickupName até ${formatTime(booking.beThereBy!)}. O motorista para e te pega.',
                    style: AppText.bodyStrong,
                  ),
                ),
              ]),
            ),
          const SizedBox(height: Space.sm),
          if (booking.boardingCode != null)
            BoraCard(
              child: Row(
                children: [
                  const Expanded(child: Text('Código de embarque\nMostre ao motorista', style: AppText.label)),
                  Text(booking.boardingCode!, style: AppText.display.copyWith(letterSpacing: 6)),
                ],
              ),
            ),
          if (r != null) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Avatar(r.driver.initial),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.driver.fullName, style: AppText.bodyStrong),
                      Text('${r.vehicle.model} ${r.vehicle.color}', style: AppText.caption),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(6)),
                  child: Text(r.vehicle.plate,
                      style: const TextStyle(color: AppColors.night, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(child: BoraButton(label: 'Detalhes', kind: BoraButtonKind.secondary, onPressed: onDetails)),
              const SizedBox(width: Space.sm),
              Expanded(child: BoraButton(label: 'Fechar', kind: BoraButtonKind.ghost, onPressed: onClose)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  const _TopChip({required this.text, this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(999), boxShadow: Shadows.soft),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: AppText.bodyStrong),
            if (sub != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(sub!, style: AppText.caption.copyWith(color: AppColors.green)),
              ]),
          ],
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
        decoration: BoxDecoration(color: AppColors.scrim, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: AppText.caption.copyWith(color: AppColors.text)),
      );
}


/// Uma linha que resume como embarcar ("Vá até o carro" ou "Vá até a parada").
class _ModeLine extends StatelessWidget {
  const _ModeLine({required this.offer});
  final RideOffer offer;

  @override
  Widget build(BuildContext context) {
    final car = offer.pickupByCar;
    final text = car
        ? 'Vá até o carro · ${offer.pickupWalkM ?? 0} m · sai às ${formatTime(offer.pickupEta ?? offer.ride.departureAt)}'
        : 'Parada ${offer.pickup?.name ?? ''} · esteja lá às ${offer.beThereBy == null ? '--' : formatTime(offer.beThereBy!)}';
    return Row(children: [
      Icon(car ? Icons.directions_walk : Icons.directions_bus_outlined, size: 15, color: AppColors.green),
      const SizedBox(width: 4),
      Flexible(child: Text(text, style: AppText.caption.copyWith(color: AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
  }
}

/// Plano de embarque em destaque na confirmação: o que fazer e até quando.
class _PickupPlan extends StatelessWidget {
  const _PickupPlan({required this.offer});
  final RideOffer offer;

  @override
  Widget build(BuildContext context) {
    final car = offer.pickupByCar;
    final title = car ? 'Vá até o carro' : 'Vá até a parada';
    final where = car ? (offer.ride.originLabel ?? offer.pickup?.name ?? 'Saída do motorista') : (offer.pickup?.name ?? 'Parada');
    final steps = <(IconData, String)>[
      (Icons.directions_walk, '${offer.pickupWalkM ?? 0} m a pé${offer.walkMin == null ? '' : ' (${offer.walkMin} min)'} até $where'),
      if (offer.leaveBy != null) (Icons.schedule, 'Saia até ${formatTime(offer.leaveBy!)}'),
      if (offer.beThereBy != null)
        (Icons.flag_outlined, car ? 'Esteja no carro até ${formatTime(offer.beThereBy!)}' : 'Esteja na parada até ${formatTime(offer.beThereBy!)}'),
      if (!car && offer.pickupEta != null) (Icons.directions_car_filled, 'O motorista passa e para às ${formatTime(offer.pickupEta!)}'),
    ];
    return BoraCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(car ? Icons.directions_car_filled : Icons.directions_bus, color: AppColors.green),
            const SizedBox(width: Space.xs),
            Text(title, style: AppText.subtitle),
            const Spacer(),
            Pill(car ? 'Pertinho do carro' : 'Embarque no caminho', color: AppColors.mint),
          ]),
          const SizedBox(height: Space.sm),
          for (final (icon, text) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 17, color: AppColors.textMuted),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(text, style: AppText.body.copyWith(color: AppColors.text))),
              ]),
            ),
        ],
      ),
    );
  }
}
