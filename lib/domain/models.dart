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
    this.email,
    this.firstNameRaw,
    this.lastName,
    this.language = 'pt-BR',
    this.termsAccepted = false,
    this.paymentPref,
    this.hasCpf = false,
  });
  final String id;
  final String? phone;
  final String? email;
  final String? firstNameRaw;
  final String? lastName;
  final String language;
  final bool termsAccepted;
  final String? paymentPref;
  final bool hasCpf;
  final String? fullName;
  final Gender? gender;
  final VerificationStatus identityStatus;
  final bool womenOnlyPref;
  final bool onboardingDone;
  final double ratingAvg;
  final int ratingCount;
  final EmergencyContact? emergencyContact;

  String get firstName => (firstNameRaw ?? (fullName ?? '').trim().split(' ').first);

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        phone: m['phone'] as String?,
        firstNameRaw: m['first_name'] as String?,
        lastName: m['last_name'] as String?,
        language: m['preferred_language'] as String? ?? 'pt-BR',
        termsAccepted: m['terms_accepted_at'] != null,
        paymentPref: m['payment_pref'] as String?,
        hasCpf: m['cpf'] != null,
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
    this.hasShelter,
    this.isLit,
  });
  final String id;
  final String name;
  final String region;
  final LatLng point;
  final bool boardable;
  final bool? hasShelter;
  final bool? isLit;

  factory Stop.fromMap(Map<String, dynamic> m) => Stop(
        id: m['id'] as String,
        name: m['name'] as String,
        region: m['region'] as String,
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        boardable: m['boardable'] as bool? ?? true,
        hasShelter: m['has_shelter'] as bool?,
        isLit: m['is_lit'] as bool?,
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
    this.originLabel,
    this.destLabel,
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

  /// Rótulos da rota real (viagens publicadas com origem/destino livres).
  final String? originLabel;
  final String? destLabel;

  bool get hasRealRoute => originLabel != null || destLabel != null;

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
      originLabel: m['origin_label'] as String?,
      destLabel: m['dest_label'] as String?,
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
    this.pickupByCar = false,
    this.pickupEta,
    this.pickupName,
    this.cancelledBy,
  });
  final String id;
  final String rideId;

  /// 'passenger', 'driver', 'ride' (viagem cancelada) ou 'no_show' (não apareceu).
  final String? cancelledBy;

  /// true = o passageiro vai a pé até o carro na saída; false = espera numa parada.
  final bool pickupByCar;

  /// Horário combinado em que o carro passa no embarque.
  final DateTime? pickupEta;
  final String? pickupName;

  /// Até quando estar no ponto (2 min antes do carro).
  DateTime? get beThereBy => pickupEta?.subtract(const Duration(minutes: 2));
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
        pickupByCar: m['pickup_mode'] == 'car',
        pickupEta: m['pickup_eta'] == null ? null : DateTime.parse(m['pickup_eta'] as String).toLocal(),
        pickupName: m['pickup_name'] as String?,
        cancelledBy: m['cancelled_by'] as String?,
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
    this.pickup,
    this.dropoff,
    this.pickupWalkM,
    this.dropoffWalkM,
    this.pickupEta,
    this.dropoffEta,
    this.pickupByCar = false,
    this.walkMin,
    this.beThereBy,
    this.leaveBy,
  });
  final Ride ride;

  /// "Ir até o carro" (perto da saída) ou "ir até a parada" (mais longe).
  final bool pickupByCar;
  final int? walkMin;
  final DateTime? beThereBy;
  final DateTime? leaveBy;
  final String pickupStopId;
  final String dropoffStopId;
  final int distanceM;
  final int priceCents;
  final List<String> sharedCommunities;

  /// Vêm da busca por proximidade (search_rides_near).
  final Stop? pickup;
  final Stop? dropoff;
  final int? pickupWalkM;
  final int? dropoffWalkM;
  final DateTime? pickupEta;
  final DateTime? dropoffEta;

  static Stop? _stop(Object? raw) {
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw as Map);
    return Stop(
      id: m['id'] as String,
      name: m['name'] as String,
      region: '',
      point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
    );
  }

  static DateTime? _date(Object? raw) => raw == null ? null : DateTime.parse(raw as String).toLocal();

  factory RideOffer.fromMap(Map<String, dynamic> m) => RideOffer(
        ride: Ride.fromMap(Map<String, dynamic>.from(m['ride'] as Map)),
        pickupStopId: m['pickup_stop_id'] as String,
        dropoffStopId: m['dropoff_stop_id'] as String,
        distanceM: (m['distance_m'] as num).toInt(),
        priceCents: (m['price_cents'] as num).toInt(),
        sharedCommunities: [for (final c in (m['shared_communities'] as List? ?? const [])) c as String],
        pickup: _stop(m['pickup']),
        dropoff: _stop(m['dropoff']),
        pickupWalkM: (m['pickup'] as Map?)?['walk_m'] as int?,
        dropoffWalkM: (m['dropoff'] as Map?)?['walk_m'] as int?,
        pickupEta: _date(m['pickup_eta']),
        dropoffEta: _date(m['dropoff_eta']),
        pickupByCar: m['pickup_mode'] == 'car',
        walkMin: (m['walk_min'] as num?)?.toInt(),
        beThereBy: _date(m['be_there_by']),
        leaveBy: _date(m['leave_by']),
      );
}

/// Carro no mapa. Para quem não tem reserva, a posição vem arredondada (~150 m).
class NearbyDriver {
  const NearbyDriver({required this.rideId, required this.point, this.heading, required this.seatsAvailable, required this.isMyRide});
  final String rideId;
  final LatLng point;
  final double? heading;
  final int seatsAvailable;
  final bool isMyRide;

  factory NearbyDriver.fromMap(Map<String, dynamic> m) => NearbyDriver(
        rideId: m['ride_id'] as String,
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        heading: (m['heading'] as num?)?.toDouble(),
        seatsAvailable: (m['seats_available'] as num).toInt(),
        isMyRide: m['is_my_ride'] as bool? ?? false,
      );
}

/// Acompanhamento de uma viagem reservada.
class RideTracking {
  const RideTracking({required this.live, this.driverPoint, this.heading, this.pickupEta, this.metersToPickup, required this.status});
  final bool live;
  final LatLng? driverPoint;
  final double? heading;
  final DateTime? pickupEta;
  final int? metersToPickup;
  final RideStatus status;

  factory RideTracking.fromMap(Map<String, dynamic> m) => RideTracking(
        live: m['live'] as bool? ?? false,
        driverPoint: m['lat'] == null ? null : LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        heading: (m['heading'] as num?)?.toDouble(),
        pickupEta: m['pickup_eta'] == null ? null : DateTime.parse(m['pickup_eta'] as String).toLocal(),
        metersToPickup: (m['meters_to_pickup'] as num?)?.toInt(),
        status: _enumBySnake(RideStatus.values, m['status'], RideStatus.open),
      );
}

/// Lugar vindo da busca de endereços (ou do pin no mapa).
class Place {
  const Place({required this.label, required this.point, this.detail});
  final String label;
  final String? detail;
  final LatLng point;
}

/// Erro já com mensagem pronta para a tela.
class BoraException implements Exception {
  const BoraException(this.message);
  final String message;
  @override
  String toString() => message;
}


/// Evento (jogo, show, festa...) com as caronas organizadas em volta.
class BoraEvent {
  const BoraEvent({
    required this.id,
    required this.name,
    required this.kind,
    required this.venueLabel,
    required this.point,
    required this.startsAt,
    required this.endsAt,
    required this.inviteCode,
    this.description = '',
    this.meetingPoint,
    this.communityName,
    this.isMine = false,
    this.distanceM,
    this.ridesIda = 0,
    this.ridesVolta = 0,
    this.seats = 0,
    this.interested = 0,
    this.myInterest = const {},
  });

  final String id;
  final String name;
  final String kind;
  final String venueLabel;
  final LatLng point;
  final DateTime startsAt;
  final DateTime endsAt;
  final String inviteCode;
  final String description;
  final String? meetingPoint;
  final String? communityName;
  final bool isMine;
  final int? distanceM;
  final int ridesIda;
  final int ridesVolta;
  final int seats;
  final int interested;

  /// 'ida' e/ou 'volta' quando a pessoa marcou "preciso de carona".
  final Set<String> myInterest;

  bool get happeningNow => DateTime.now().isAfter(startsAt) && DateTime.now().isBefore(endsAt);

  factory BoraEvent.fromMap(Map<String, dynamic> m) => BoraEvent(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: m['kind'] as String? ?? 'outro',
        venueLabel: m['venue_label'] as String,
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(m['ends_at'] as String).toLocal(),
        inviteCode: m['invite_code'] as String,
        description: m['description'] as String? ?? '',
        meetingPoint: m['meeting_point'] as String?,
        communityName: m['community_name'] as String?,
        isMine: m['is_mine'] as bool? ?? false,
        distanceM: (m['distance_m'] as num?)?.toInt(),
        ridesIda: (m['rides_ida'] as num?)?.toInt() ?? 0,
        ridesVolta: (m['rides_volta'] as num?)?.toInt() ?? 0,
        seats: (m['seats'] as num?)?.toInt() ?? 0,
        interested: (m['interested'] as num?)?.toInt() ?? 0,
        myInterest: {for (final l in (m['my_interest'] as List? ?? const [])) l as String},
      );
}

// ---------------------------------------------------------------------------
// Corrida: o que o motorista ainda tem que fazer no caminho
// ---------------------------------------------------------------------------

/// Pegar ou deixar um passageiro numa parada.
class NavAction {
  const NavAction({required this.bookingId, required this.pickup, required this.status, required this.byCar, this.passenger});
  final String bookingId;

  /// true = pegar; false = deixar.
  final bool pickup;
  final BookingStatus status;
  final bool byCar;
  final Person? passenger;

  String get name => passenger?.firstName ?? 'Passageiro';

  factory NavAction.fromMap(Map<String, dynamic> m) => NavAction(
        bookingId: m['booking_id'] as String,
        pickup: m['kind'] == 'pickup',
        status: _enumBySnake(BookingStatus.values, m['status'], BookingStatus.reserved),
        byCar: m['pickup_mode'] == 'car',
        passenger: m['passenger'] == null ? null : Person.fromMap(Map<String, dynamic>.from(m['passenger'] as Map)),
      );
}

/// Parada com alguém para pegar ou deixar.
class NavStop {
  const NavStop({required this.stopId, required this.name, required this.point, required this.distanceM, this.eta, required this.actions});
  final String stopId;
  final String name;
  final LatLng point;

  /// Distância desde o começo da rota publicada.
  final int distanceM;
  final DateTime? eta;
  final List<NavAction> actions;

  List<NavAction> get pickups => actions.where((a) => a.pickup).toList();
  List<NavAction> get dropoffs => actions.where((a) => !a.pickup).toList();

  factory NavStop.fromMap(Map<String, dynamic> m) => NavStop(
        stopId: m['stop_id'] as String,
        name: m['name'] as String,
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        distanceM: (m['distance_m'] as num?)?.toInt() ?? 0,
        eta: m['eta'] == null ? null : DateTime.parse(m['eta'] as String).toLocal(),
        actions: [for (final a in m['actions'] as List) NavAction.fromMap(Map<String, dynamic>.from(a as Map))],
      );
}

/// Tudo que a navegação precisa: paradas pendentes em ordem, destino e
/// uma versão que muda quando entra, sai ou embarca alguém.
class NavPlan {
  const NavPlan({
    required this.ride,
    required this.route,
    required this.destination,
    required this.destinationLabel,
    required this.stops,
    required this.version,
  });
  final Ride ride;
  final List<LatLng> route;
  final LatLng destination;
  final String destinationLabel;
  final List<NavStop> stops;
  final String version;

  factory NavPlan.fromMap(Map<String, dynamic> m) {
    final coords = ((m['route'] as Map?)?['coordinates'] as List?) ?? const [];
    final d = Map<String, dynamic>.from(m['destination'] as Map);
    return NavPlan(
      ride: Ride.fromMap(Map<String, dynamic>.from(m['ride'] as Map)),
      route: [for (final c in coords) LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble())],
      destination: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
      destinationLabel: d['label'] as String? ?? 'Destino',
      stops: [for (final s in m['stops'] as List) NavStop.fromMap(Map<String, dynamic>.from(s as Map))],
      version: m['version'] as String? ?? '',
    );
  }
}

/// Avaliação que eu ainda devo depois de uma viagem.
class PendingRating {
  const PendingRating({
    required this.bookingId,
    required this.rideId,
    required this.ratingDriver,
    required this.person,
    this.when,
    this.from,
    this.to,
  });
  final String bookingId;
  final String rideId;

  /// true = eu fui de carona e avalio o motorista; false = eu dirigi e avalio o passageiro.
  final bool ratingDriver;
  final Person person;
  final DateTime? when;
  final String? from;
  final String? to;

  factory PendingRating.fromMap(Map<String, dynamic> m) => PendingRating(
        bookingId: m['booking_id'] as String,
        rideId: m['ride_id'] as String,
        ratingDriver: m['rated_role'] == 'driver',
        person: Person.fromMap(Map<String, dynamic>.from(m['person'] as Map)),
        when: m['when'] == null ? null : DateTime.parse(m['when'] as String).toLocal(),
        from: m['from'] as String?,
        to: m['to'] as String?,
      );
}
