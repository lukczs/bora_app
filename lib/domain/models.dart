import 'package:latlong2/latlong.dart';

enum Gender { female, male, other }

enum VerificationStatus { pending, inReview, approved, rejected }

enum RideStatus { open, inProgress, completed, cancelled }

enum BookingStatus { reserved, boarded, completed, cancelled }

enum RideVisibility { public, communities }

enum CommunityKind { education, company, residential, corridor, group }

enum CommunityJoinMode { inviteCode, approval }

enum MemberRole { owner, admin, member }

enum MemberStatus { pending, active, banned }

T _enumBySnake<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw == null) return fallback;
  final camel = raw.toString().replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
  for (final v in values) {
    if (v.name == camel) return v;
  }
  return fallback;
}

String enumToSnake(Enum e) =>
    e.name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

Gender? _gender(Object? raw) => raw == null ? null : _enumBySnake(Gender.values, raw, Gender.other);

class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone, required this.relation});
  final String name;
  final String phone;
  final String relation;

  factory EmergencyContact.fromMap(Map<String, dynamic> m) => EmergencyContact(
      name: m['name'] as String, phone: m['phone'] as String, relation: m['relation'] as String);
}

/// O que dá para saber de outra pessoa (sem CPF, telefone ou nascimento).
class Person {
  const Person({
    required this.id,
    required this.fullName,
    this.gender,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });
  final String id;
  final String fullName;
  final Gender? gender;
  final double ratingAvg;
  final int ratingCount;

  String get firstName => fullName.trim().split(' ').first;
  String get initial => fullName.trim().isEmpty ? '?' : fullName.trim().substring(0, 1).toUpperCase();
  String get ratingLabel => ratingCount == 0
      ? 'Ainda sem avaliações'
      : 'Nota ${ratingAvg.toStringAsFixed(1).replaceAll('.', ',')} em $ratingCount viagens';

  factory Person.fromMap(Map<String, dynamic> m) => Person(
        id: m['id'] as String,
        fullName: (m['full_name'] as String?) ?? 'Sem nome',
        gender: _gender(m['gender']),
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
      );
}

/// O usuário logado.
class AppUser {
  const AppUser({
    required this.id,
    this.phone,
    this.fullName,
    this.gender,
    required this.identityStatus,
    required this.womenOnlyPref,
    required this.onboardingDone,
    required this.ratingAvg,
    required this.ratingCount,
    this.emergencyContact,
  });
  final String id;
  final String? phone;
  final String? fullName;
  final Gender? gender;
  final VerificationStatus identityStatus;
  final bool womenOnlyPref;
  final bool onboardingDone;
  final double ratingAvg;
  final int ratingCount;
  final EmergencyContact? emergencyContact;

  String get firstName => (fullName ?? '').trim().split(' ').first;

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        phone: m['phone'] as String?,
        fullName: m['full_name'] as String?,
        gender: _gender(m['gender']),
        identityStatus: _enumBySnake(VerificationStatus.values, m['identity_status'], VerificationStatus.pending),
        womenOnlyPref: m['women_only_pref'] as bool? ?? false,
        onboardingDone: m['onboarding_done'] as bool? ?? false,
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
        emergencyContact: m['emergency_contact'] == null
            ? null
            : EmergencyContact.fromMap(Map<String, dynamic>.from(m['emergency_contact'] as Map)),
      );
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.ownerId,
    required this.plate,
    required this.brand,
    required this.model,
    required this.color,
    required this.seats,
  });
  final String id;
  final String ownerId;
  final String plate;
  final String brand;
  final String model;
  final String color;
  final int seats;

  String get label => '$brand $model $color';

  factory Vehicle.fromMap(Map<String, dynamic> m) => Vehicle(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        plate: m['plate'] as String,
        brand: m['brand'] as String,
        model: m['model'] as String,
        color: m['color'] as String,
        seats: (m['seats'] as num).toInt(),
      );
}

class Stop {
  const Stop({
    required this.id,
    required this.name,
    required this.region,
    required this.point,
    this.boardable = true,
  });
  final String id;
  final String name;
  final String region;
  final LatLng point;
  final bool boardable;

  factory Stop.fromMap(Map<String, dynamic> m) => Stop(
        id: m['id'] as String,
        name: m['name'] as String,
        region: m['region'] as String,
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        boardable: m['boardable'] as bool? ?? true,
      );
}

class Community {
  const Community({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.joinMode,
    required this.inviteCode,
    required this.memberCount,
    required this.myRole,
    required this.myStatus,
    this.anchorStopId,
  });
  final String id;
  final String name;
  final String description;
  final CommunityKind kind;
  final CommunityJoinMode joinMode;
  final String inviteCode;
  final int memberCount;
  final MemberRole myRole;
  final MemberStatus myStatus;
  final String? anchorStopId;

  bool get iAmAdmin => myStatus == MemberStatus.active && myRole != MemberRole.member;

  factory Community.fromMap(Map<String, dynamic> m) => Community(
        id: m['id'] as String,
        name: m['name'] as String,
        description: (m['description'] as String?) ?? '',
        kind: _enumBySnake(CommunityKind.values, m['kind'], CommunityKind.group),
        joinMode: _enumBySnake(CommunityJoinMode.values, m['join_mode'], CommunityJoinMode.inviteCode),
        inviteCode: m['invite_code'] as String,
        memberCount: (m['member_count'] as num?)?.toInt() ?? 0,
        myRole: _enumBySnake(MemberRole.values, m['my_role'], MemberRole.member),
        myStatus: _enumBySnake(MemberStatus.values, m['my_status'], MemberStatus.active),
        anchorStopId: m['anchor_stop_id'] as String?,
      );
}

class CommunityMemberView {
  const CommunityMemberView({required this.person, required this.role, required this.status});
  final Person person;
  final MemberRole role;
  final MemberStatus status;

  factory CommunityMemberView.fromMap(Map<String, dynamic> m) => CommunityMemberView(
        person: Person.fromMap(Map<String, dynamic>.from(m['person'] as Map)),
        role: _enumBySnake(MemberRole.values, m['role'], MemberRole.member),
        status: _enumBySnake(MemberStatus.values, m['status'], MemberStatus.active),
      );
}

class Ride {
  const Ride({
    required this.id,
    required this.driver,
    required this.vehicle,
    required this.path,
    required this.distanceM,
    required this.departureAt,
    required this.recurringDays,
    required this.seatsTotal,
    required this.seatsAvailable,
    required this.womenOnly,
    required this.visibility,
    required this.status,
    required this.communityNames,
    required this.communityIds,
    this.bookings = const [],
  });
  final String id;
  final Person driver;
  final Vehicle vehicle;
  final List<String> path;
  final int distanceM;
  final DateTime departureAt;
  final List<int> recurringDays;
  final int seatsTotal;
  final int seatsAvailable;
  final bool womenOnly;
  final RideVisibility visibility;
  final RideStatus status;
  final List<String> communityNames;
  final List<String> communityIds;

  /// Só vem preenchido nas viagens em que eu sou o motorista.
  final List<Booking> bookings;

  String get originStopId => path.first;
  String get destinationStopId => path.last;

  factory Ride.fromMap(Map<String, dynamic> m) {
    final communities = [for (final c in (m['communities'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)];
    return Ride(
      id: m['id'] as String,
      driver: Person.fromMap(Map<String, dynamic>.from(m['driver'] as Map)),
      vehicle: Vehicle.fromMap(Map<String, dynamic>.from(m['vehicle'] as Map)),
      path: [for (final s in m['path'] as List) s as String],
      distanceM: (m['distance_m'] as num).toInt(),
      departureAt: DateTime.parse(m['departure_at'] as String).toLocal(),
      recurringDays: [for (final d in (m['recurring_days'] as List? ?? const [])) (d as num).toInt()],
      seatsTotal: (m['seats_total'] as num).toInt(),
      seatsAvailable: (m['seats_available'] as num).toInt(),
      womenOnly: m['women_only'] as bool? ?? false,
      visibility: _enumBySnake(RideVisibility.values, m['visibility'], RideVisibility.public),
      status: _enumBySnake(RideStatus.values, m['status'], RideStatus.open),
      communityNames: [for (final c in communities) c['name'] as String],
      communityIds: [for (final c in communities) c['id'] as String],
      bookings: [
        for (final b in (m['bookings'] as List? ?? const []))
          Booking.fromMap(Map<String, dynamic>.from(b as Map)),
      ],
    );
  }
}

class Booking {
  const Booking({
    required this.id,
    required this.rideId,
    required this.pickupStopId,
    required this.dropoffStopId,
    required this.distanceM,
    required this.priceCents,
    required this.status,
    required this.createdAt,
    this.boardingCode,
    this.passenger,
    this.sharedCommunities = const [],
    this.ride,
  });
  final String id;
  final String rideId;
  final String pickupStopId;
  final String dropoffStopId;
  final int distanceM;
  final int priceCents;
  final BookingStatus status;
  final DateTime createdAt;

  /// Só o passageiro recebe o código. O motorista confere digitando.
  final String? boardingCode;

  /// Preenchido quando quem olha é o motorista.
  final Person? passenger;
  final List<String> sharedCommunities;

  /// Preenchido quando quem olha é o passageiro.
  final Ride? ride;

  factory Booking.fromMap(Map<String, dynamic> m) => Booking(
        id: m['id'] as String,
        rideId: m['ride_id'] as String,
        pickupStopId: m['pickup_stop_id'] as String,
        dropoffStopId: m['dropoff_stop_id'] as String,
        distanceM: (m['distance_m'] as num).toInt(),
        priceCents: (m['price_cents'] as num).toInt(),
        status: _enumBySnake(BookingStatus.values, m['status'], BookingStatus.reserved),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        boardingCode: m['boarding_code'] as String?,
        passenger: m['passenger'] == null ? null : Person.fromMap(Map<String, dynamic>.from(m['passenger'] as Map)),
        sharedCommunities: [for (final c in (m['shared_communities'] as List? ?? const [])) c as String],
        ride: m['ride'] == null ? null : Ride.fromMap(Map<String, dynamic>.from(m['ride'] as Map)),
      );
}

class RideOffer {
  const RideOffer({
    required this.ride,
    required this.pickupStopId,
    required this.dropoffStopId,
    required this.distanceM,
    required this.priceCents,
    required this.sharedCommunities,
  });
  final Ride ride;
  final String pickupStopId;
  final String dropoffStopId;
  final int distanceM;
  final int priceCents;
  final List<String> sharedCommunities;

  factory RideOffer.fromMap(Map<String, dynamic> m) => RideOffer(
        ride: Ride.fromMap(Map<String, dynamic>.from(m['ride'] as Map)),
        pickupStopId: m['pickup_stop_id'] as String,
        dropoffStopId: m['dropoff_stop_id'] as String,
        distanceM: (m['distance_m'] as num).toInt(),
        priceCents: (m['price_cents'] as num).toInt(),
        sharedCommunities: [for (final c in (m['shared_communities'] as List? ?? const [])) c as String],
      );
}

/// Erro já com mensagem pronta para a tela.
class BoraException implements Exception {
  const BoraException(this.message);
  final String message;
  @override
  String toString() => message;
}
