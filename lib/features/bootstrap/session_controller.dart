import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/credential_store.dart';
import '../../data/dto/shift_dto.dart';

/// Where the app is allowed to be.
enum AppPhase {
  /// Reading the keystore. Nothing is decided yet.
  starting,

  /// Never paired, or unpaired since. Only the setup flow is reachable.
  needsPairing,

  /// Paired, nobody signed in. Only the sign-in screen is reachable.
  needsShift,

  /// Signed in: the floor, the menu and the cart are reachable.
  ready,
}

class AppSession {
  const AppSession({required this.phase, this.credentials, this.notice});

  final AppPhase phase;
  final StoredCredentials? credentials;

  /// A string key to show once on the screen the app lands on — "this device was unpaired", or
  /// "your shift ended" — so a staff member is told why they were sent back.
  final String? notice;

  String? get staffName => credentials?.staffName;
  bool get canTakeOverTables => credentials?.canTakeOverTables ?? false;

  AppSession copyWith({AppPhase? phase, StoredCredentials? credentials, String? notice}) =>
      AppSession(
        phase: phase ?? this.phase,
        credentials: credentials ?? this.credentials,
        notice: notice,
      );
}

final sessionProvider = NotifierProvider<AppSessionController, AppSession>(
  AppSessionController.new,
);

/// Owns the pairing/shift lifecycle, and is the only thing that decides which part of the app is
/// reachable. The router reads it; nothing else may change the phase.
class AppSessionController extends Notifier<AppSession> {
  StreamSubscription<SessionEvent>? _events;

  @override
  AppSession build() {
    final api = ref.watch(apiClientProvider);
    _events = api.sessionEvents.listen(_onSessionEvent);
    ref.onDispose(() => _events?.cancel());
    // build() must be synchronous; the keystore read continues in the background and lands on
    // one of the three decided phases.
    Future.microtask(restore);
    return const AppSession(phase: AppPhase.starting);
  }

  /// Reads what is on the device and decides the phase. Also refreshes the long-lived device
  /// token, so a handset that stays in the shop never reaches its expiry.
  Future<void> restore() async {
    final store = ref.read(credentialStoreProvider);
    final credentials = await store.load();
    if (credentials == null) {
      state = const AppSession(phase: AppPhase.needsPairing);
      return;
    }
    state = AppSession(
      phase: credentials.hasShift ? AppPhase.ready : AppPhase.needsShift,
      credentials: credentials,
      notice: state.notice,
    );
    // Best effort: an offline handset must still show its floor from cache rather than be thrown
    // back to pairing because one refresh call could not reach the server.
    unawaited(_refreshDeviceTokenQuietly());
  }

  Future<void> _refreshDeviceTokenQuietly() async {
    try {
      await ref.read(shiftRepositoryProvider).refreshDeviceToken();
    } on Object {
      // A revoked handset arrives as a SessionEvent from the interceptor, handled below.
    }
  }

  /// Called by the setup flow once pairing succeeded.
  Future<void> onPaired() async {
    final credentials = await ref.read(credentialStoreProvider).load();
    state = AppSession(phase: AppPhase.needsShift, credentials: credentials);
  }

  /// Called by the sign-in screen once a shift started.
  Future<void> onShiftStarted(ShiftSession session) async {
    final credentials = await ref.read(credentialStoreProvider).load();
    state = AppSession(phase: AppPhase.ready, credentials: credentials);
  }

  /// Ends the shift, giving back every table this handset holds.
  Future<void> signOut() async {
    try {
      await ref.read(shiftRepositoryProvider).logout();
    } finally {
      final credentials = await ref.read(credentialStoreProvider).load();
      state = AppSession(phase: AppPhase.needsShift, credentials: credentials);
    }
  }

  /// Unpairs the handset. Requires a manager account to set up again, which is the point.
  Future<void> unpair() async {
    await ref.read(credentialStoreProvider).clearPairing();
    state = const AppSession(phase: AppPhase.needsPairing);
  }

  void _onSessionEvent(SessionEvent event) {
    switch (event) {
      case SessionEvent.deviceRevoked:
        unawaited(ref.read(credentialStoreProvider).clearPairing());
        state = const AppSession(
          phase: AppPhase.needsPairing,
          notice: 'error.deviceRevoked',
        );
      case SessionEvent.shiftEnded:
        unawaited(ref.read(credentialStoreProvider).clearShift());
        state = AppSession(
          phase: AppPhase.needsShift,
          credentials: ref.read(credentialStoreProvider).cached,
          notice: 'login.shiftEnded',
        );
    }
  }

  /// Clears the one-shot notice after a screen has shown it.
  void acknowledgeNotice() {
    if (state.notice != null) state = state.copyWith(notice: null);
  }
}

/// The handset's branch/terminal/printing configuration. Read once per shift.
final configProvider = FutureProvider<StaffAppConfig>((ref) async {
  // Re-read whenever the phase changes, so the config never outlives the shift it belongs to.
  final session = ref.watch(sessionProvider);
  if (session.phase != AppPhase.ready) {
    throw StateError('config is only available during a shift');
  }
  return ref.watch(shiftRepositoryProvider).config();
});
