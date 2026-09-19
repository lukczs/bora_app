import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Stop stop(String id) =>
      graph.stops[id] ?? Stop(id: id, name: id, region: '', point: _fallbackPosition);

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
    final stops = await _client.from('stops').select();
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
    notifyListeners();
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
  Future<void> sendCode(String phoneE164) => _client.auth.signInWithOtp(phone: phoneE164);

  Future<void> verifyCode({required String phoneE164, required String code}) =>
      _client.auth.verifyOTP(phone: phoneE164, token: code, type: OtpType.sms);

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

  Future<void> signOut() => _client.auth.signOut();

  // ------------------------------------------------------------------
  // Cadastro
  // ------------------------------------------------------------------
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
    super.dispose();
  }
}
