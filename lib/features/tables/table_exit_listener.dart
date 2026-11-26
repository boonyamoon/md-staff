import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../router/app_router.dart';
import '../zones/zones_controller.dart';
import 'active_table_controller.dart';

/// Wraps the table's screens and gets the waiter off them the moment the table stops being theirs.
///
/// Two ways that happens, both of which must be explained rather than silently failing on the next
/// tap: a manager took the table over (the lease renew or the send comes back TABLE_CLAIM_LOST),
/// or the cashier opened its bill at the POS.
class TableExitListener extends ConsumerStatefulWidget {
  const TableExitListener({super.key, required this.floorItemId, required this.child});

  final String floorItemId;
  final Widget child;

  @override
  ConsumerState<TableExitListener> createState() => _TableExitListenerState();
}

class _TableExitListenerState extends ConsumerState<TableExitListener> {
  bool _handling = false;

  Future<void> _handle(TableExitReason reason) async {
    if (_handling) return;
    _handling = true;
    final t = ref.read(stringsProvider);
    ref.read(activeTableProvider.notifier).acknowledgeExit();

    final (title, body) = switch (reason) {
      TableExitReason.claimLost => (t('claim.lost.title'), t('claim.lost.body')),
      TableExitReason.pendingPayment => (t('tables.pendingPayment'), t('error.pendingPayment')),
    };

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded, color: MeedColors.danger, size: 32),
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.4)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('common.ok')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Someone else changed this table, so the floor on the way back is fetched again.
    unawaited(ref.read(zonesProvider.notifier).refresh());
    AppRoutes.goZones(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeTableProvider, (previous, next) {
      final reason = next.exitReason;
      if (reason != null && previous?.exitReason != reason) {
        _handle(reason);
      }
    });
    return widget.child;
  }
}
