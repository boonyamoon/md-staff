import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/credential_store.dart';
import '../../data/dto/session_dto.dart';

/// Where the app is allowed to be. There are only three, because a handset's sign-in is
/// permanent: once signed in it stays signed in until someone ends it.
enum AppPhase {
  /// Reading the keystore. Nothing is decided yet.
  starting,

  /// Never signed in, or signed out since. Only the sign-in flow is reachable.
  needsLogin,

  /// Signed in: the floor, the menu and the cart are reachable.
  ready,
}

class AppSession {
  const AppSession({required this.phase, this.session, this.notice});

  final AppPhase phase;
  final StaffSession? session;

  /// A string key to show once on the screen the app lands on — "this handset was signed out" —
  /// so a staff member is told why, rather than just finding themselves at a login form.
  final String? notice;

  String? get staffName => session?.staffName;
  String? get terminalName => session?.terminalName;
  String? get terminalCode => session?.terminalCode;
  bool get canTakeOverTables => session?.canTakeOverTables ?? false;

  AppSession copyWith({AppPhase? phase, StaffSession? session, String? notice}) => AppSession(
        phase: phase ?? this.phase,
        session: session ?? this.session,
        notice: notice,
      );
}

final sessionProvider = NotifierProvider<AppSessionController, AppSession>(
  AppSessionController.new,
);

/// Owns the sign-in lifecycle, and is the only thing that decides which part of the app is
/// reachable. The router reads it; nothing else may change the phase.
class AppSessionController extends Notifier<AppSession> {
  StreamSubscription<SessionEvent>? _events;

  @override
  AppSession build() {
    final api = ref.watch(apiClientProvider);
    // The client refreshes the token on its own; this is how it does it without knowing about
    // the repository layer.
    api.attachRefresher(() => ref.read(sessionRepositoryProvider).refresh());
    _events = api.sessionEvents.listen(_onSessionEvent);
    ref.onDispose(() => _events?.cancel());
    // build() must be synchronous; the keystore read continues in the background.
    Future.microtask(restore);
    return const AppSession(phase: AppPhase.starting);
  }

  /// Reads what is on the device and decides the phase.
  ///
  /// Deliberately does NOT call the server: a handset that opens with no signal must still show
  /// its floor from the token it holds rather than be bounced to a login form. If that token has
  /// lapsed, the first real request refreshes it, and only a genuine revocation signs the
  /// handset out.
  Future<void> restore() async {
    final session = await ref.read(credentialStoreProvider).load();
    state = AppSession(
      phase: session == null ? AppPhase.needsLogin : AppPhase.ready,
      session: session,
      notice: state.notice,
    );
  }

  /// Called by the sign-in flow once the handset is paired and signed in.
  Future<void> onSignedIn(StaffAppSession _) async {
    final session = await ref.read(credentialStoreProvider).load();
    state = AppSession(phase: session == null ? AppPhase.needsLogin : AppPhase.ready, session: session);
  }

  /// Signs the handset out: the server revokes the session and releases any tables it holds.
  Future<void> signOut() async {
    try {
      await ref.read(sessionRepositoryProvider).logout();
    } finally {
      state = const AppSession(phase: AppPhase.needsLogin);
    }
  }

  void _onSessionEvent(SessionEvent event) {
    switch (event) {
      case SessionEvent.signedOut:
        unawaited(ref.read(credentialStoreProvider).clear());
        state = const AppSession(phase: AppPhase.needsLogin, notice: 'login.signedOut');
    }
  }

  /// Clears the one-shot notice after a screen has shown it.
  void acknowledgeNotice() {
    if (state.notice != null) state = state.copyWith(notice: null);
  }
}

/// The handset's branch/terminal/printing configuration. Read once per sign-in and per launch.
final configProvider = FutureProvider<StaffAppConfig>((ref) async {
  // Re-read whenever the phase changes, so the config never outlives the session it belongs to.
  final phase = ref.watch(sessionProvider.select((s) => s.phase));
  if (phase != AppPhase.ready) {
    throw StateError('config is only available once signed in');
  }
  final credentials = ref.read(credentialStoreProvider);
  final config = await ref.watch(sessionRepositoryProvider).config();
  if (config.branch.reportsThemeColor) {
    await credentials.saveThemeColor(
      branchId: config.branch.branchId,
      color: config.branch.themeColor,
    );
  }
  return config;
});
