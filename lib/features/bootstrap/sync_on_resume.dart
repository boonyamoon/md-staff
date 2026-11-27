import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../menu/menu_catalog_controller.dart';
import '../zones/zones_controller.dart';
import 'session_controller.dart';

/// Brings the offline copies up to date when the waiter returns to the app — only those old enough
/// to need it.
class SyncOnResume extends ConsumerStatefulWidget {
  const SyncOnResume({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncOnResume> createState() => _SyncOnResumeState();
}

class _SyncOnResumeState extends ConsumerState<SyncOnResume> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _sync);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _sync() {
    if (ref.read(signedInBranchProvider) == null) return;
    unawaited(ref.read(zonesProvider.notifier).refreshIfStale());
    unawaited(ref.read(menuCatalogProvider.notifier).refreshIfStale());
  }

  @override
  Widget build(BuildContext context) {
    // Followed for as long as the app runs. Left to itself it is only brought up to date when a
    // screen next asks, which after signing in again is while that screen is being built — too late
    // to tell the floor and the menu that the branch is back.
    ref.listen(signedInBranchProvider, (_, _) {});
    return widget.child;
  }
}
