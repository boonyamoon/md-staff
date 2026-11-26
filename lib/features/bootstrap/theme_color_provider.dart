import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../setup/setup_controller.dart';
import 'session_controller.dart';

/// The branch's `theme_color`, which the whole app is tinted with.
///
/// Signed in, it is what `staff-app/config` reports; until that answers (or when the handset is
/// offline) it is the colour remembered with the session. While signing in, it is the branch
/// picked so far, so the choice shows at once. Without any of these — or with a value that is not
/// a colour — it is [MeedColors.defaultPrimary].
final themeColorProvider = Provider<Color>((ref) {
  final phase = ref.watch(sessionProvider.select((s) => s.phase));
  final hex = switch (phase) {
    AppPhase.starting => null,
    AppPhase.needsLogin => ref.watch(
        setupControllerProvider.select((s) => s.selectedBranch?.themeColor),
      ),
    AppPhase.ready => _signedInColor(ref),
  };
  return themeColorFrom(hex);
});

String? _signedInColor(Ref ref) {
  final session = ref.watch(sessionProvider.select((s) => s.session));
  final branch = ref.watch(configProvider.select((c) => c.value?.branch));
  // The branch check matters right after signing in somewhere else: until the new config arrives,
  // the provider still holds the previous branch's.
  if (branch != null && branch.reportsThemeColor && branch.branchId == session?.branchId) {
    return branch.themeColor;
  }
  return session?.themeColor;
}
