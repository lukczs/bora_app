import 'dart:convert';
import 'dart:io';

import 'package:bora/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lê com os modelos do app as respostas REAIS da API guardadas pelo teste
/// de ponta a ponta (supabase/tests/e2e_api.py, pasta api_fixtures).
/// Pega erro de leitura (campo que mudou de nome, número que veio como texto…)
/// antes de chegar no celular. Sem a pasta, não roda nada.
void main() {
  final dir = Directory(Platform.environment['API_FIXTURES'] ?? 'api_fixtures');
  if (!dir.existsSync()) {
    test('sem respostas da API para conferir', () {}, skip: 'rode o workflow "Testar o app"');
    return;
  }

  Map<String, dynamic> m(Object? o) => Map<String, dynamic>.from(o as Map);
  final parsers = <String, void Function(Object?)>{
    'my_profile': (j) => AppUser.fromMap(m(j)),
    'vehicles': (j) => [for (final v in j as List) Vehicle.fromMap(m(v))],
    'stops_in_view': (j) => [for (final s in j as List) Stop.fromMap(m(s))],
    'search_rides_near': (j) => [for (final o in j as List) RideOffer.fromMap(m(o))],
    'event_rides': (j) => [for (final o in j as List) RideOffer.fromMap(m(o))],
    'my_rides': (j) => [for (final r in j as List) Ride.fromMap(m(r))],
    'my_bookings': (j) => [for (final b in j as List) Booking.fromMap(m(b))],
    'my_bookings_done': (j) => [for (final b in j as List) Booking.fromMap(m(b))],
    'nearby_drivers': (j) => [for (final d in j as List) NearbyDriver.fromMap(m(d))],
    'track_ride': (j) => RideTracking.fromMap(m(j)),
    'my_communities': (j) => [for (final c in j as List) Community.fromMap(m(c))],
    'community_members_list': (j) => [for (final c in j as List) CommunityMemberView.fromMap(m(c))],
    'upcoming_events': (j) => [for (final e in j as List) BoraEvent.fromMap(m(e))],
    'event_json': (j) => BoraEvent.fromMap(m(j)),
    'driver_navigation': (j) {
      final plan = NavPlan.fromMap(m(j));
      expect(plan.stops, isNotEmpty);
      expect(plan.route.length, greaterThan(1));
    },
  };

  for (final e in parsers.entries) {
    final f = File('${dir.path}/${e.key}.json');
    test('app lê ${e.key}', () {
      expect(f.existsSync(), isTrue, reason: 'o teste da API não salvou ${e.key}');
      e.value(jsonDecode(f.readAsStringSync()));
    });
  }
}
