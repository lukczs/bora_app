import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/bora_button.dart';
import '../data/bora_store.dart';
import '../data/errors.dart';
import '../features/auth/dev_login_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/phone_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/bookings/booking_screen.dart';
import '../features/communities/community_screens.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/document_screen.dart';
import '../features/onboarding/emergency_contact_screen.dart';
import '../features/onboarding/location_screen.dart';
import '../features/onboarding/register_screen.dart';
import '../features/rides/driver_ride_screen.dart';
import '../features/rides/publish_ride_screen.dart';
import '../features/rides/vehicle_form_screen.dart';
import '../features/search/offer_detail_screen.dart';
import '../features/search/search_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final store = ref.read(storeProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: store,
    redirect: (context, state) {
      final path = state.matchedLocation;
      final inAuth = const ['/welcome', '/phone', '/otp', '/dev-login'].contains(path);
      final inOnboarding = path.startsWith('/onboarding');

      switch (store.status) {
        case GateStatus.loading:
        case GateStatus.failed:
          return path == '/splash' ? null : '/splash';
        case GateStatus.signedOut:
          return inAuth ? null : '/welcome';
        case GateStatus.needsOnboarding:
          return inOnboarding ? null : '/onboarding/register';
        case GateStatus.ready:
          return (inAuth || inOnboarding || path == '/splash') ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, s) => OtpScreen(phoneE164: s.uri.queryParameters['phone'] ?? ''),
      ),
      GoRoute(path: '/dev-login', builder: (_, __) => const DevLoginScreen()),
      GoRoute(path: '/onboarding/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/onboarding/emergency', builder: (_, __) => const EmergencyContactScreen()),
      GoRoute(path: '/onboarding/document', builder: (_, __) => const DocumentScreen()),
      GoRoute(path: '/onboarding/location', builder: (_, __) => const LocationScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(
        path: '/search',
        builder: (_, s) => SearchScreen(initialPickupStopId: s.uri.queryParameters['pickup']),
      ),
      GoRoute(path: '/offer/:rideId', builder: (_, s) => OfferDetailScreen(rideId: s.pathParameters['rideId']!)),
      GoRoute(path: '/booking/:id', builder: (_, s) => BookingScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(
        path: '/publish',
        builder: (_, s) => PublishRideScreen(editRideId: s.uri.queryParameters['edit']),
      ),
      GoRoute(path: '/my-ride/:id', builder: (_, s) => DriverRideScreen(rideId: s.pathParameters['id']!)),
      GoRoute(path: '/vehicle', builder: (_, s) => VehicleFormScreen(vehicleId: s.uri.queryParameters['id'])),
      GoRoute(path: '/community/new', builder: (_, __) => const CreateCommunityScreen()),
      GoRoute(path: '/community/join', builder: (_, __) => const JoinCommunityScreen()),
      GoRoute(
        path: '/community/:id',
        builder: (_, s) => CommunityDetailScreen(communityId: s.pathParameters['id']!),
      ),
    ],
  );
});

class _Splash extends ConsumerWidget {
  const _Splash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return Scaffold(
      body: Center(
        child: store.status != GateStatus.failed
            ? const CircularProgressIndicator(color: AppColors.green)
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, color: AppColors.textMuted, size: 44),
                    const SizedBox(height: 16),
                    Text(friendlyError(store.failure ?? ''), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    BoraButton(label: 'Tentar de novo', onPressed: store.bootstrap),
                    const SizedBox(height: 12),
                    BoraButton(label: 'Sair desta conta', secondary: true, onPressed: store.signOut),
                  ],
                ),
              ),
      ),
    );
  }
}
