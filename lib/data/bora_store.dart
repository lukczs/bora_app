import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/map/map_types.dart';
import '../domain/models.dart';
import 'route_graph.dart';

enum GateStatus { loading, signedOut, needsOnboarding, ready, failed }

/// Estado do app + todas as chamadas ao Supabase num lugar só.
/// As telas leem os dados daqui (síncrono) e chamam as ações (assíncronas);
/// cada ação recarrega o que mudou e chama notifyListeners().
class BoraStore extends ChangeNotifier {
  BoraStore(this._client) {
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.tokenRefreshed) return;
      bootstrap();
    });
    bootstrap();
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _authSub;

  static const _fallbackPosition = LatLng(-15.7938, -47.8828); // Rodoviária do Plano

  GateStatus status = GateStatus.loading;
  String? failure;

  AppUser? me;
  RouteGraph graph = RouteGraph(const [], const []);
  LatLng position = _fallbackPosition;
  bool positionIsReal = false;
  List<Vehicle> myVehicles = const [];
  List<Community> myCommunities = const [];
  List<Ride> myRides = const [];
  List<Booking> myBookings = const [];
  List<List<String>> openRidePaths = const [];

  /// Última busca, para a tela de detalhe reaproveitar sem ir ao servidor de novo.
  final Map<String, RideOffer> _offers = {};

  /// Paradas carregadas sob demanda (são quase 2.000; o app não baixa todas).
  final Map<String, Stop> _stopCache = {};

  Stop stop(String id) =>
      graph.stops[id] ?? _stopCache[id] ?? Stop(id: id, name: 'Parada', region: '', point: _fallbackPosition);

  void _cacheStops(Iterable<Stop> stops) {
    for (final s in stops) {
      _stopCache[s.id] = s;
    }
  }

  /// Garante nome e posição das paradas citadas em viagens e reservas.
  Future<void> ensureStops(Iterable<String> ids) async {
    final missing = ids.where((id) => !graph.stops.containsKey(id) && !_stopCache.containsKey(id)).toSet().toList();
    if (missing.isEmpty) return;
    final data = await _client.rpc('stops_by_ids', params: {'p_ids': missing}) as List;
    _cacheStops([for (final m in data) Stop.fromMap(Map<String, dynamic>.from(m as Map))]);
  }

  RideOffer? offer(String rideId) => _offers[rideId];
  Ride? myRide(String id) => myRides.where((r) => r.id == id).firstOrNull;
  Booking? myBooking(String id) => myBookings.where((b) => b.id == id).firstOrNull;

  // ------------------------------------------------------------------
  // Carga
  // ------------------------------------------------------------------
  bool _booting = false;
  bool _bootAgain = false;

  Future<void> bootstrap() async {
    if (_booting) {
      _bootAgain = true;
      return;
    }
    _booting = true;
    try {
      await _bootstrap();
    } finally {
      _booting = false;
      if (_bootAgain) {
        _bootAgain = false;
        unawaited(bootstrap());
      }
    }
  }

  Future<void> _bootstrap() async {
    if (_client.auth.currentUser == null) {
      me = null;
      _set(GateStatus.signedOut);
      return;
    }
    if (status == GateStatus.signedOut || status == GateStatus.failed) _set(GateStatus.loading);
    try {
      await refreshProfile();
      if (me == null) throw const BoraException('Perfil não encontrado. O schema.sql foi aplicado no Supabase?');
      if (!me!.onboardingDone) {
        _set(GateStatus.needsOnboarding);
        return;
      }
      await Future.wait([_loadGraph(), refreshVehicles(), refreshCommunities(), refreshTrips()]);
      unawaited(locate());
      _set(GateStatus.ready);
    } catch (e) {
      failure = e.toString();
      _set(GateStatus.failed);
    }
  }

  void _set(GateStatus s) {
    status = s;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    final data = await _client.rpc('my_profile');
    me = data == null ? null : AppUser.fromMap(Map<String, dynamic>.from(data as Map));
    notifyListeners();
  }

  Future<void> _loadGraph() async {
    // Só as paradas do grafo antigo; as do OpenStreetMap vêm sob demanda.
    final stops = await _client.from('stops').select().eq('source', 'manual');
    final links = await _client.from('stop_links').select();
    graph = RouteGraph(
      [for (final s in stops) Stop.fromMap(s)],
      [for (final l in links) (l['a'] as String, l['b'] as String)],
    );
  }

  Future<void> refreshVehicles() async {
    final rows = await _client.from('vehicles').select().order('brand');
    myVehicles = [for (final r in rows) Vehicle.fromMap(r)];
    notifyListeners();
  }

  Future<void> refreshCommunities() async {
    final data = await _client.rpc('my_communities') as List;
    myCommunities = [for (final c in data) Community.fromMap(Map<String, dynamic>.from(c as Map))];
    notifyListeners();
  }

  /// Minhas viagens, minhas reservas e o panorama de viagens abertas.
  Future<void> refreshTrips() async {
    final results = await Future.wait<dynamic>([
      _client.rpc('my_rides'),
      _client.rpc('my_bookings'),
      _client.rpc('open_rides_overview'),
    ]);
    myRides = [for (final r in results[0] as List) Ride.fromMap(Map<String, dynamic>.from(r as Map))];
    myBookings = [for (final b in results[1] as List) Booking.fromMap(Map<String, dynamic>.from(b as Map))];
    openRidePaths = [
      for (final r in results[2] as List) [for (final s in (r as Map)['path'] as List) s as String],
    ];
    await ensureStops([
      for (final r in myRides) ...[if (r.path.isNotEmpty) r.path.first, if (r.path.isNotEmpty) r.path.last],
      for (final r in myRides) for (final b in r.bookings) ...[b.pickupStopId, b.dropoffStopId],
      for (final b in myBookings) ...[b.pickupStopId, b.dropoffStopId],
    ]);
    _syncPresence();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Mapa: paradas visíveis, carros por perto, acompanhamento
  // ------------------------------------------------------------------
  Future<List<Stop>> stopsInView(GeoBounds b) async {
    final data = await _client.rpc('stops_in_view', params: {
      'p_south': b.south,
      'p_west': b.west,
      'p_north': b.north,
      'p_east': b.east,
    }) as List;
    final stops = [for (final m in data) Stop.fromMap(Map<String, dynamic>.from(m as Map))];
    _cacheStops(stops);
    return stops;
  }

  Future<List<NearbyDriver>> nearbyDrivers(LatLng center, {int radiusM = 4000}) async {
    final data = await _client.rpc('nearby_drivers', params: {
      'p_lat': center.latitude,
      'p_lng': center.longitude,
      'p_radius_m': radiusM,
    }) as List;
    return [for (final m in data) NearbyDriver.fromMap(Map<String, dynamic>.from(m as Map))];
  }

  Future<RideTracking> trackRide(String rideId) async {
    final data = await _client.rpc('track_ride', params: {'p_ride': rideId});
    return RideTracking.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<List<LatLng>> rideRoute(String rideId) async {
    final data = await _client.rpc('ride_route', params: {'p_ride': rideId});
    if (data == null) return const [];
    final coords = (data as Map)['coordinates'] as List;
    return [for (final c in coords) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())];
  }

  // Motorista com viagem saindo em breve compartilha a posição (só enquanto durar).
  Timer? _presenceTimer;

  Ride? get activeDriverRide {
    final now = DateTime.now();
    return myRides
        .where((r) =>
            r.status == RideStatus.inProgress ||
            (r.status == RideStatus.open &&
                r.departureAt.isAfter(now.subtract(const Duration(minutes: 30))) &&
                r.departureAt.isBefore(now.add(const Duration(minutes: 90)))))
        .firstOrNull;
  }

  void _syncPresence() {
    final active = activeDriverRide != null;
    if (active && _presenceTimer == null) {
      unawaited(_sendPresence());
      _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) => _sendPresence());
    } else if (!active && _presenceTimer != null) {
      _presenceTimer!.cancel();
      _presenceTimer = null;
      unawaited(_client.rpc('stop_sharing_location').then((_) {}, onError: (_) {}));
    }
  }

  Future<void> _sendPresence() async {
    try {
      final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));
      position = LatLng(p.latitude, p.longitude);
      positionIsReal = true;
      final kept = await _client.rpc('update_my_location',
          params: {'p_lat': p.latitude, 'p_lng': p.longitude, 'p_heading': p.heading});
      if (kept == false) _syncPresence();
    } catch (_) {
      // sem GPS agora; tenta no próximo ciclo
    }
  }

  /// GPS de verdade, com plano B: sem permissão, ou longe demais do DF, usa a Rodoviária.
  Future<bool> locate({bool askPermission = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && askPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return false;
      }
      final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 12));
      final here = LatLng(p.latitude, p.longitude);
      if (graph.metersBetween(here, _fallbackPosition) > 120000) return false; // fora do DF
      position = here;
      positionIsReal = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Autenticação
  // ------------------------------------------------------------------
  Future<void> sendCode(String phoneE164, {bool create = true}) =>
      _client.auth.signInWithOtp(phone: phoneE164, shouldCreateUser: create);

  Future<void> verifyCode({required String phoneE164, required String code}) =>
      _client.auth.verifyOTP(phone: phoneE164, token: code, type: OtpType.sms);

  /// Código por e-mail (alternativa ao SMS).
  Future<void> sendEmailCode(String email, {bool create = true}) =>
      _client.auth.signInWithOtp(email: email.trim().toLowerCase(), shouldCreateUser: create);

  Future<void> verifyEmailCode({required String email, required String code}) =>
      _client.auth.verifyOTP(email: email.trim().toLowerCase(), token: code, type: OtpType.email);

  /// Login social (Google, Apple, Facebook) pelo navegador.
  Future<void> signInWithProvider(OAuthProvider provider) async {
    await _client.auth.signInWithOAuth(provider, redirectTo: 'br.com.bora://login-callback');
  }

  /// Senha opcional criada no cadastro (para entrar sem código depois).
  Future<void> setPassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  String? get authEmail => _client.auth.currentUser?.email;
  String? get authPhone => _client.auth.currentUser?.phone;

  /// Entrada alternativa para desenvolvimento, enquanto o SMS não está configurado.
  Future<void> devEmailSignIn({required String email, required String password, required bool create}) async {
    if (create) {
      final res = await _client.auth.signUp(email: email, password: password);
      if (res.session == null) {
        throw const BoraException(
            'Conta criada, mas o Supabase pediu confirmação por e-mail. Desative "Confirm email" em Authentication > Sign In / Providers > Email, ou confirme pelo link.');
      }
    } else {
      await _client.auth.signInWithPassword(email: email, password: password);
    }
  }

  /// Login com Google pelo navegador; volta ao app pelo link br.com.bora://login-callback.
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: 'br.com.bora://login-callback');
  }

  Future<void> signOut() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    await _client.auth.signOut();
  }

  // ------------------------------------------------------------------
  // Cadastro
  // ------------------------------------------------------------------
  Future<void> saveBasicProfile({required String firstName, required String lastName, required String language}) async {
    await _client.rpc('save_basic_profile',
        params: {'p_first_name': firstName, 'p_last_name': lastName, 'p_language': language});
    await refreshProfile();
  }

  Future<void> acceptTerms() async {
    await _client.rpc('accept_terms');
    await refreshProfile();
  }

  Future<void> setPaymentPref(String? pref) async {
    await _client.rpc('set_payment_pref', params: {'p_pref': pref ?? ''});
    await refreshProfile();
  }

  Future<void> submitIdentity({
    required String cpfDigits,
    required DateTime birthDate,
    required Gender gender,
    required bool womenOnlyPref,
  }) async {
    await _client.rpc('submit_identity', params: {
      'p_cpf': cpfDigits,
      'p_birth_date': birthDate.toIso8601String().substring(0, 10),
      'p_gender': enumToSnake(gender),
      'p_women_only_pref': womenOnlyPref,
    });
    await refreshProfile();
  }

  Future<void> submitRegistration({
    required String fullName,
    required String cpfDigits,
    required DateTime birthDate,
    required Gender gender,
    required bool womenOnlyPref,
  }) async {
    await _client.rpc('submit_registration', params: {
      'p_full_name': fullName,
      'p_cpf': cpfDigits,
      'p_birth_date': birthDate.toIso8601String().substring(0, 10),
      'p_gender': enumToSnake(gender),
      'p_women_only_pref': womenOnlyPref,
    });
    await refreshProfile();
  }

  Future<void> saveEmergencyContact(EmergencyContact c) async {
    await _client.rpc('save_emergency_contact',
        params: {'p_name': c.name, 'p_phone': c.phone, 'p_relation': c.relation});
    await refreshProfile();
  }

  Future<void> submitIdentityDocuments() async {
    await _client.rpc('submit_identity_documents');
    await refreshProfile();
  }

  Future<void> finishOnboarding() async {
    await _client.rpc('finish_onboarding');
    await bootstrap(); // muda o status e o router leva para a Home
  }

  // ------------------------------------------------------------------
  // Carros
  // ------------------------------------------------------------------
  Future<void> saveVehicle({
    String? vehicleId,
    required String plate,
    required String brand,
    required String model,
    required String color,
    required int seats,
  }) async {
    final row = {
      'plate': plate.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''),
      'brand': brand,
      'model': model,
      'color': color,
      'seats': seats,
    };
    if (vehicleId == null) {
      await _client.from('vehicles').insert(row);
    } else {
      await _client.from('vehicles').update(row).eq('id', vehicleId);
    }
    await refreshVehicles();
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _client.from('vehicles').delete().eq('id', vehicleId);
    await refreshVehicles();
  }

  // ------------------------------------------------------------------
  // Viagens (motorista)
  // ------------------------------------------------------------------
  Future<String> publishRide({
    required String vehicleId,
    required List<String> path,
    required DateTime departureAt,
    required int seats,
    required List<int> recurringDays,
    required bool womenOnly,
    required List<String> communityIds,
  }) async {
    final id = await _client.rpc('publish_ride', params: {
      'p_vehicle': vehicleId,
      'p_path': path,
      'p_departure': departureAt.toUtc().toIso8601String(),
      'p_seats': seats,
      'p_recurring': recurringDays,
      'p_women_only': womenOnly,
      'p_communities': communityIds.isEmpty ? null : communityIds,
    });
    await refreshTrips();
    return id as String;
  }

  /// Publica com a rota real (origem e destino livres).
  Future<({String rideId, int stops, int distanceM})> publishRideRoute({
    required String vehicleId,
    required Map<String, dynamic> routeGeoJson,
    required String originLabel,
    required String destLabel,
    required DateTime departureAt,
    required int seats,
    required List<int> recurringDays,
    required bool womenOnly,
    required List<String> communityIds,
  }) async {
    final data = await _client.rpc('publish_ride_route', params: {
      'p_vehicle': vehicleId,
      'p_route': routeGeoJson,
      'p_origin_label': originLabel,
      'p_dest_label': destLabel,
      'p_departure': departureAt.toUtc().toIso8601String(),
      'p_seats': seats,
      'p_recurring': recurringDays,
      'p_women_only': womenOnly,
      'p_communities': communityIds.isEmpty ? null : communityIds,
    }) as Map;
    await refreshTrips();
    return (
      rideId: data['ride_id'] as String,
      stops: (data['stops'] as num).toInt(),
      distanceM: (data['distance_m'] as num).toInt(),
    );
  }

  // ------------------------------------------------------------------
  // Eventos
  // ------------------------------------------------------------------
  Future<List<BoraEvent>> upcomingEvents() async {
    final data = await _client.rpc('upcoming_events', params: {'p_lat': position.latitude, 'p_lng': position.longitude}) as List;
    return [for (final m in data) BoraEvent.fromMap(Map<String, dynamic>.from(m as Map))];
  }

  Future<BoraEvent?> event(String id) async {
    final data = await _client.rpc('event_json', params: {'p_event': id, 'p_lat': position.latitude, 'p_lng': position.longitude});
    return data == null ? null : BoraEvent.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<BoraEvent?> eventByCode(String code) async {
    final data = await _client.rpc('event_by_code', params: {'p_code': code});
    return data == null ? null : BoraEvent.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<List<BoraEvent>> similarEvents(LatLng p, DateTime startsAt) async {
    final data = await _client.rpc('similar_events', params: {
      'p_lat': p.latitude,
      'p_lng': p.longitude,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
    }) as List;
    return [for (final m in data) BoraEvent.fromMap(Map<String, dynamic>.from(m as Map))];
  }

  Future<String> createEvent({
    required String name,
    required String kind,
    required String venueLabel,
    required LatLng point,
    required DateTime startsAt,
    required DateTime endsAt,
    String? meetingPoint,
    String description = '',
    String? communityId,
  }) async {
    final id = await _client.rpc('create_event', params: {
      'p_name': name,
      'p_kind': kind,
      'p_venue_label': venueLabel,
      'p_lat': point.latitude,
      'p_lng': point.longitude,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
      'p_meeting_point': meetingPoint,
      'p_description': description,
      'p_community': communityId,
    });
    return id as String;
  }

  Future<void> cancelEvent(String id) => _client.rpc('cancel_event', params: {'p_event': id});

  /// Caronas do evento a até 5 km de [from] (ida) ou de [from] na volta.
  Future<List<RideOffer>> eventRides(String eventId, String leg, LatLng from) async {
    final data = await _client.rpc('event_rides', params: {
      'p_event': eventId,
      'p_leg': leg,
      'p_lat': from.latitude,
      'p_lng': from.longitude,
    }) as List;
    final offers = [for (final o in data) RideOffer.fromMap(Map<String, dynamic>.from(o as Map))];
    _offers.addEntries(offers.map((o) => MapEntry(o.ride.id, o)));
    _cacheStops([for (final o in offers) ...[if (o.pickup != null) o.pickup!, if (o.dropoff != null) o.dropoff!]]);
    return offers;
  }

  Future<void> setEventInterest(String eventId, String leg, LatLng at, bool on) => _client.rpc('set_event_interest',
      params: {'p_event': eventId, 'p_leg': leg, 'p_lat': at.latitude, 'p_lng': at.longitude, 'p_on': on});

  Future<int> eventDemand(String eventId, String leg, Map<String, dynamic> routeGeoJson) async {
    try {
      final n = await _client.rpc('event_demand', params: {'p_event': eventId, 'p_leg': leg, 'p_route': routeGeoJson});
      return (n as num).toInt();
    } catch (_) {
      return 0;
    }
  }

  Future<({String rideId, int stops, int distanceM})> publishEventRide({
    required String eventId,
    required String leg,
    required String vehicleId,
    required Map<String, dynamic> routeGeoJson,
    required String originLabel,
    required String destLabel,
    required DateTime departureAt,
    required int seats,
    required bool womenOnly,
  }) async {
    final data = await _client.rpc('publish_event_ride', params: {
      'p_event': eventId,
      'p_leg': leg,
      'p_vehicle': vehicleId,
      'p_route': routeGeoJson,
      'p_origin_label': originLabel,
      'p_dest_label': destLabel,
      'p_departure': departureAt.toUtc().toIso8601String(),
      'p_seats': seats,
      'p_women_only': womenOnly,
    }) as Map;
    await refreshTrips();
    return (
      rideId: data['ride_id'] as String,
      stops: (data['stops'] as num).toInt(),
      distanceM: (data['distance_m'] as num).toInt(),
    );
  }

  /// Quantas buscas sem resultado passaram perto desta rota nos últimos 14 dias.
  Future<int> demandNearRoute(Map<String, dynamic> routeGeoJson) async {
    try {
      final n = await _client.rpc('demand_near_route', params: {'p_route': routeGeoJson});
      return (n as num).toInt();
    } catch (_) {
      return 0;
    }
  }

  Future<void> updateRide(String rideId,
      {required DateTime departureAt, required int seats, required List<int> recurringDays}) async {
    await _client.rpc('update_ride', params: {
      'p_ride': rideId,
      'p_departure': departureAt.toUtc().toIso8601String(),
      'p_seats': seats,
      'p_recurring': recurringDays,
    });
    await refreshTrips();
  }

  Future<void> cancelRide(String rideId) async {
    await _client.rpc('cancel_ride', params: {'p_ride': rideId});
    await refreshTrips();
  }

  // ------------------------------------------------------------------
  // Corrida (motorista)
  // ------------------------------------------------------------------
  Future<void> startRide(String rideId) async {
    await _client.rpc('start_ride', params: {'p_ride': rideId});
    await refreshTrips();
  }

  Future<NavPlan> driverNavigation(String rideId) async {
    final data = await _client.rpc('driver_navigation', params: {'p_ride': rideId});
    return NavPlan.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<void> boardPassenger(String bookingId) => _client.rpc('board_passenger', params: {'p_booking': bookingId});
  Future<void> passengerNoShow(String bookingId) => _client.rpc('passenger_no_show', params: {'p_booking': bookingId});
  Future<void> dropPassenger(String bookingId) => _client.rpc('drop_passenger', params: {'p_booking': bookingId});

  Future<void> finishRide(String rideId) async {
    await _client.rpc('finish_ride', params: {'p_ride': rideId});
    await refreshTrips();
  }

  /// Posição do carro durante a navegação (mais frequente que o normal).
  Future<void> reportLocation(LatLng p, double? heading) async {
    position = p;
    positionIsReal = true;
    try {
      await _client.rpc('update_my_location', params: {'p_lat': p.latitude, 'p_lng': p.longitude, 'p_heading': heading});
    } catch (_) {
      // sem rede agora; manda de novo no próximo ponto
    }
  }

  // ------------------------------------------------------------------
  // Busca e reservas (passageiro)
  // ------------------------------------------------------------------
  Future<List<RideOffer>> searchRides({
    required String pickupStopId,
    required String dropoffStopId,
    required bool onlyMyCommunities,
  }) async {
    final data = await _client.rpc('search_rides', params: {
      'p_pickup': pickupStopId,
      'p_dropoff': dropoffStopId,
      'p_only_my_communities': onlyMyCommunities,
    }) as List;
    final offers = [for (final o in data) RideOffer.fromMap(Map<String, dynamic>.from(o as Map))];
    _offers
      ..clear()
      ..addEntries(offers.map((o) => MapEntry(o.ride.id, o)));
    return offers;
  }

  /// Busca por ponto: onde estou -> para onde vou.
  Future<List<RideOffer>> searchNear({required LatLng from, required LatLng to, bool onlyMyCommunities = false}) async {
    final data = await _client.rpc('search_rides_near', params: {
      'p_from_lat': from.latitude,
      'p_from_lng': from.longitude,
      'p_to_lat': to.latitude,
      'p_to_lng': to.longitude,
      'p_only_my_communities': onlyMyCommunities,
    }) as List;
    final offers = [for (final o in data) RideOffer.fromMap(Map<String, dynamic>.from(o as Map))];
    _offers
      ..clear()
      ..addEntries(offers.map((o) => MapEntry(o.ride.id, o)));
    _cacheStops([for (final o in offers) ...[if (o.pickup != null) o.pickup!, if (o.dropoff != null) o.dropoff!]]);
    return offers;
  }

  Future<String> bookSeat({required String rideId, required String pickupStopId, required String dropoffStopId}) async {
    final id = await _client
        .rpc('book_seat', params: {'p_ride': rideId, 'p_pickup': pickupStopId, 'p_dropoff': dropoffStopId});
    await refreshTrips();
    return id as String;
  }

  Future<void> cancelBooking(String bookingId) async {
    await _client.rpc('cancel_booking', params: {'p_booking': bookingId});
    await refreshTrips();
  }

  // ------------------------------------------------------------------
  // Comunidades
  // ------------------------------------------------------------------
  Future<void> createCommunity({
    required String name,
    required String description,
    required CommunityKind kind,
    required CommunityJoinMode joinMode,
    String? anchorStopId,
  }) async {
    await _client.rpc('create_community', params: {
      'p_name': name,
      'p_description': description,
      'p_kind': enumToSnake(kind),
      'p_join_mode': enumToSnake(joinMode),
      'p_anchor_stop': anchorStopId,
    });
    await refreshCommunities();
  }

  /// Devolve true se entrou direto, false se ficou aguardando aprovação.
  Future<bool> joinCommunity(String inviteCode) async {
    final status = await _client.rpc('join_community', params: {'p_invite_code': inviteCode});
    await Future.wait([refreshCommunities(), refreshTrips()]);
    return status == 'active';
  }

  Future<void> leaveCommunity(String communityId) async {
    await _client.rpc('leave_community', params: {'p_community': communityId});
    await Future.wait([refreshCommunities(), refreshTrips()]);
  }

  Future<List<CommunityMemberView>> communityMembers(String communityId) async {
    final data = await _client.rpc('community_members_list', params: {'p_community': communityId}) as List;
    return [for (final m in data) CommunityMemberView.fromMap(Map<String, dynamic>.from(m as Map))];
  }

  Future<void> setMemberStatus(String communityId, String userId, MemberStatus status) async {
    await _client.rpc('set_member_status',
        params: {'p_community': communityId, 'p_user': userId, 'p_status': enumToSnake(status)});
    await refreshCommunities();
  }

  @override
  void dispose() {
    _authSub.cancel();
    _presenceTimer?.cancel();
    super.dispose();
  }
}
