import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/bootstrap/session_controller.dart';
import '../features/bootstrap/splash_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/login/login_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/tables/table_bill_screen.dart';
import '../features/tables/tables_screen.dart';
import '../features/zones/zones_screen.dart';

/// Every path in the app, and the only way to navigate between them.
class AppRoutes {
  const AppRoutes._();

  static const splash = '/';
  static const setup = '/setup';
  static const login = '/login';
  static const zones = '/zones';
  static const settings = '/settings';

  static String zone(String zoneId) => '/zones/$zoneId';
  static String menu(String floorItemId) => '/table/$floorItemId';
  static String cart(String floorItemId) => '/table/$floorItemId/cart';
  static String bill(String floorItemId) => '/table/$floorItemId/bill';

  static void goZones(BuildContext context) => context.go(zones);
  static void goZone(BuildContext context, String zoneId) => context.push(zone(zoneId));
  static void goMenu(BuildContext context, String floorItemId) => context.push(menu(floorItemId));
  static void goCart(BuildContext context, String floorItemId) => context.push(cart(floorItemId));
  static void goBill(BuildContext context, String floorItemId) => context.push(bill(floorItemId));
  static void goSettings(BuildContext context) => context.push(settings);
}

final routerProvider = Provider<GoRouter>((ref) {
  // One listenable fed by the session phase: pairing, sign-in and the floor are mutually
  // exclusive, and the redirect below is what enforces that rather than each screen checking.
  final phase = ValueNotifier<AppPhase>(ref.read(sessionProvider).phase);
  ref.listen(sessionProvider, (previous, next) => phase.value = next.phase);
  ref.onDispose(phase.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: phase,
    redirect: (context, state) {
      final current = phase.value;
      final location = state.matchedLocation;

      switch (current) {
        case AppPhase.starting:
          return location == AppRoutes.splash ? null : AppRoutes.splash;
        case AppPhase.needsPairing:
          return location == AppRoutes.setup ? null : AppRoutes.setup;
        case AppPhase.needsShift:
          return location == AppRoutes.login ? null : AppRoutes.login;
        case AppPhase.ready:
          // A signed-in handset has no business on the splash, setup or sign-in screens.
          const gated = {AppRoutes.splash, AppRoutes.setup, AppRoutes.login};
          return gated.contains(location) ? AppRoutes.zones : null;
      }
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.setup, builder: (context, state) => const SetupScreen()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.zones,
        builder: (context, state) => const ZonesScreen(),
        routes: [
          GoRoute(
            path: ':zoneId',
            builder: (context, state) =>
                TablesScreen(zoneId: state.pathParameters['zoneId'] ?? ''),
          ),
        ],
      ),
      GoRoute(
        path: '/table/:floorItemId',
        builder: (context, state) =>
            MenuScreen(floorItemId: state.pathParameters['floorItemId'] ?? ''),
        routes: [
          GoRoute(
            path: 'cart',
            builder: (context, state) =>
                CartScreen(floorItemId: state.pathParameters['floorItemId'] ?? ''),
          ),
          GoRoute(
            path: 'bill',
            builder: (context, state) =>
                TableBillScreen(floorItemId: state.pathParameters['floorItemId'] ?? ''),
          ),
        ],
      ),
      GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
    ],
  );
});
