import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../data/dto/session_dto.dart';
import '../../data/dto/setup_dto.dart';

enum SetupStep {
  login,
  branch,
  terminal,

  /// Signed in, but the account belongs to no store at all.
  noBusiness,

  /// Signed in and has a store, but may not use staff handsets there.
  noPermission,
}

class SetupState {
  const SetupState({
    this.step = SetupStep.login,
    this.email = '',
    this.password = '',
    this.branches = const <BranchOption>[],
    this.selectedBranch,
    this.terminals = const <PairingTerminal>[],
    this.selectedTerminalId,
    this.deviceName = '',
    this.loading = false,
    this.failure,
    this.missingCredentials = false,
    this.signedIn,
  });

  final SetupStep step;
  final String email;
  final String password;
  final List<BranchOption> branches;
  final BranchOption? selectedBranch;
  final List<PairingTerminal> terminals;

  /// Null means "let the server pick any free handset terminal".
  final String? selectedTerminalId;
  final String deviceName;
  final bool loading;
  final ApiFailure? failure;
  final bool missingCredentials;

  /// Set once the handset is signed in; the screen hands this to AppSessionController.
  final StaffAppSession? signedIn;

  bool get canLogin => email.contains('@') && password.isNotEmpty && !loading;
  bool get canFinish => selectedBranch != null && deviceName.trim().isNotEmpty && !loading;

  SetupState copyWith({
    SetupStep? step,
    String? email,
    String? password,
    List<BranchOption>? branches,
    BranchOption? selectedBranch,
    List<PairingTerminal>? terminals,
    String? selectedTerminalId,
    String? deviceName,
    bool? loading,
    ApiFailure? failure,
    bool? missingCredentials,
    StaffAppSession? signedIn,
    bool clearFailure = false,
    bool clearSelectedTerminal = false,
  }) =>
      SetupState(
        step: step ?? this.step,
        email: email ?? this.email,
        password: password ?? this.password,
        branches: branches ?? this.branches,
        selectedBranch: selectedBranch ?? this.selectedBranch,
        terminals: terminals ?? this.terminals,
        selectedTerminalId:
            clearSelectedTerminal ? null : (selectedTerminalId ?? this.selectedTerminalId),
        deviceName: deviceName ?? this.deviceName,
        loading: loading ?? this.loading,
        failure: clearFailure ? null : (failure ?? this.failure),
        missingCredentials: missingCredentials ?? this.missingCredentials,
        signedIn: signedIn ?? this.signedIn,
      );
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(
  SetupController.new,
);

/// Drives the handset's one sign-in: email → branch → terminal → in.
///
/// A waiter does this once. There is no second "start a shift" step and nothing to repeat
/// tomorrow — the app keeps itself signed in from here on, and only being signed out or having
/// handset access removed brings anyone back to this screen.
///
/// The staff JWT lives in this controller only. It is never written to disk and is dropped the
/// moment the session is issued, so a handset on the floor carries no staff credentials — the
/// same rule the kiosk app's SetupViewModel follows.
class SetupController extends Notifier<SetupState> {
  String? _staffToken;

  @override
  SetupState build() {
    ref.onDispose(() => _staffToken = null);
    // Prefill the device name with the phone's own model; a manager can rename it. When the form
    // is being started over after a sign-out, the name is already known.
    ref.listen(deviceNameProvider, (previous, next) {
      final name = next.value;
      if (name != null && state.deviceName.isEmpty) {
        state = state.copyWith(deviceName: name);
      }
    });
    return SetupState(deviceName: ref.read(deviceNameProvider).value ?? '');
  }

  void emailChanged(String value) => state = state.copyWith(
        email: value.trim(),
        clearFailure: true,
        missingCredentials: false,
      );

  void passwordChanged(String value) => state = state.copyWith(
        password: value,
        clearFailure: true,
        missingCredentials: false,
      );

  void deviceNameChanged(String value) => state = state.copyWith(deviceName: value);

  void selectBranch(BranchOption branch) {
    if (state.loading) return;
    state = state.copyWith(selectedBranch: branch, clearFailure: true);
  }

  void selectTerminal(String? terminalId) => state = state.copyWith(
        selectedTerminalId: terminalId,
        clearSelectedTerminal: terminalId == null,
      );

  Future<void> login() async {
    if (!state.canLogin) {
      if (!state.loading) {
        state = state.copyWith(missingCredentials: true, clearFailure: true);
      }
      return;
    }
    await _guard(() async {
      final setup = ref.read(setupRepositoryProvider);
      final token = await setup.staffLogin(email: state.email, password: state.password);
      _staffToken = token;
      final access = await setup.access(token);

      final step = access.branches.isNotEmpty
          ? SetupStep.branch
          : (access.deniedByPermission ? SetupStep.noPermission : SetupStep.noBusiness);
      // Nothing more to do with this account — drop its token right away.
      if (step != SetupStep.branch) _staffToken = null;

      state = state.copyWith(
        step: step,
        branches: access.branches,
        selectedBranch: access.branches.length == 1 ? access.branches.first : null,
        password: '',
        clearFailure: true,
      );
    });
  }

  Future<void> confirmBranch() async {
    final branch = state.selectedBranch;
    final token = _staffToken;
    if (branch == null) return;
    if (token == null) return _backToLogin();
    await _guard(() async {
      final terminals = await ref.read(setupRepositoryProvider).terminals(
            staffBearer: token,
            branchId: branch.id,
          );
      state = state.copyWith(
        step: SetupStep.terminal,
        terminals: terminals,
        clearSelectedTerminal: true,
        clearFailure: true,
      );
    });
  }

  /// The last step: pairs the handset and signs in, in one call.
  Future<void> finish() async {
    final branch = state.selectedBranch;
    final token = _staffToken;
    if (branch == null || !state.canFinish) return;
    if (token == null) return _backToLogin();
    await _guard(() async {
      final version = await ref.read(appVersionProvider.future).catchError((_) => '1.0.0');
      final session = await ref.read(sessionRepositoryProvider).login(
            staffBearer: token,
            branchId: branch.id,
            deviceName: state.deviceName,
            appVersion: version,
            terminalId: state.selectedTerminalId,
            themeColor: branch.themeColor,
          );
      // Nothing on this handset needs the staff JWT again.
      _staffToken = null;
      state = state.copyWith(signedIn: session, clearFailure: true);
    });
  }

  void back() {
    switch (state.step) {
      case SetupStep.login:
        return;
      case SetupStep.terminal:
        state = state.copyWith(step: SetupStep.branch, clearFailure: true);
      case SetupStep.branch:
      case SetupStep.noBusiness:
      case SetupStep.noPermission:
        signOut();
    }
  }

  /// Back to the form, keeping the email so staff can retry once access is granted.
  void signOut() {
    _staffToken = null;
    _backToLogin();
  }

  void _backToLogin() => state = SetupState(email: state.email, deviceName: state.deviceName);

  Future<void> _guard(Future<void> Function() body) async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearFailure: true);
    try {
      await body();
    } on ApiFailure catch (failure) {
      state = state.copyWith(failure: failure);
    } finally {
      state = state.copyWith(loading: false);
    }
  }
}
