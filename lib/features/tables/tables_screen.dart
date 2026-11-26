import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/floor_dto.dart';
import '../../router/app_router.dart';
import '../zones/zones_controller.dart';
import 'active_table_controller.dart';
import 'take_over_sheet.dart';

/// The tables of one zone. Tapping a free or busy table claims it and goes to the menu; tapping
/// one another handset holds offers the manager-PIN takeover instead.
class TablesScreen extends ConsumerWidget {
  const TablesScreen({super.key, required this.zoneId});

  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final zones = ref.watch(zonesProvider);
    final zone = ref.watch(zoneByIdProvider(zoneId));

    return Scaffold(
      appBar: AppBar(title: Text(zone?.zoneName ?? t('tables.title'))),
      body: RefreshIndicator(
        onRefresh: () => ref.read(zonesProvider.notifier).refresh(),
        child: switch (zones) {
          AsyncError(:final error) => ErrorView(
              failure: error is ApiFailure
                  ? error
                  : ApiFailure(code: 'UNKNOWN', message: error.toString()),
              retryLabel: t('common.retry'),
              onRetry: () => ref.read(zonesProvider.notifier).refresh(),
            ),
          AsyncLoading() when zone == null => const LoadingView(),
          _ when zone == null || zone.tables.isEmpty =>
            EmptyView(message: t('tables.empty'), icon: Icons.table_bar_outlined),
          _ => _TableGrid(zone: zone, t: t),
        },
      ),
    );
  }
}

class _TableGrid extends ConsumerWidget {
  const _TableGrid({required this.zone, required this.t});

  final FloorZone zone;
  final AppStrings t;

  Future<void> _openTable(BuildContext context, WidgetRef ref, FloorTable table) async {
    final controller = ref.read(activeTableProvider.notifier);

    // Another handset has it: the only way in is a manager PIN.
    if (table.isHeldByOther) {
      final taken = await showTakeOverSheet(context, table: table);
      if (taken != true) return;
      if (!context.mounted) return;
      AppRoutes.goMenu(context, table.floorItemId);
      return;
    }

    final opened = await controller.open(table.floorItemId);
    if (!context.mounted) return;
    if (opened) {
      AppRoutes.goMenu(context, table.floorItemId);
      return;
    }

    final state = ref.read(activeTableProvider);
    // Lost the race for a free table, or a manager grabbed it a moment ago.
    if (state.failure?.code == 'TABLE_CLAIM_HELD') {
      final taken = await showTakeOverSheet(context, table: table, failure: state.failure);
      if (taken == true && context.mounted) AppRoutes.goMenu(context, table.floorItemId);
      ref.read(activeTableProvider.notifier).acknowledgeFailure();
      return;
    }
    if (state.exitReason == TableExitReason.pendingPayment) {
      _toast(context, t('error.pendingPayment'));
      ref.read(activeTableProvider.notifier).acknowledgeExit();
      return;
    }
    final failure = state.failure;
    if (failure != null) {
      _toast(context, ref.read(stringsProvider).failure(failure));
      ref.read(activeTableProvider.notifier).acknowledgeFailure();
    }
  }

  static void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context, WidgetRef ref) => GridView.builder(
        // The grid runs to the bottom edge, under the home indicator; the inset is added to the
        // scroll padding so the last row can still be scrolled clear of it.
        padding: EdgeInsets.fromLTRB(16, 16, 16, 28 + MediaQuery.paddingOf(context).bottom),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          // Two columns on a phone held in portrait: a table tile has to carry a label, a state
          // and a total, and three columns leaves no room for the holder's name.
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
        ),
        itemCount: zone.tables.length,
        itemBuilder: (context, index) {
          final table = zone.tables[index];
          return _TableTile(
            table: table,
            t: t,
            onTap: table.isOutOfService ? null : () => _openTable(context, ref, table),
          );
        },
      );
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.t, this.onTap});

  final FloorTable table;
  final AppStrings t;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (background, border, statusLabel, statusColor) = _appearance(Theme.of(context).colorScheme);
    final session = table.session;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: table.isHeldByMe ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      table.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (table.capacity != null)
                    Text(
                      '${table.capacity}',
                      style: const TextStyle(fontSize: 13, color: MeedColors.inkSoft),
                    ),
                  if (table.capacity != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.person_outline_rounded, size: 14, color: MeedColors.inkSoft),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                statusLabel,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: statusColor),
              ),
              if (table.isHeldByOther) ...[
                const SizedBox(height: 2),
                Text(
                  table.claim!.holder.staffName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: MeedColors.inkSoft),
                ),
              ],
              const Spacer(),
              if (session != null) ...[
                Text(
                  '${session.itemCount} ${t('common.items')}',
                  style: const TextStyle(fontSize: 12.5, color: MeedColors.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  t.money(session.totalAmount),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (Color, Color, String, Color) _appearance(ColorScheme scheme) {
    if (table.isOutOfService) {
      return (MeedColors.tableDisabled, MeedColors.line, t('tables.outOfService'), MeedColors.inkSoft);
    }
    if (table.isHeldByMe) {
      return (scheme.primaryTint, scheme.primary, t('tables.heldByMe'), scheme.primaryStrong);
    }
    if (table.isHeldByOther) {
      return (MeedColors.tableLocked, MeedColors.danger, t('tables.heldBy'), MeedColors.danger);
    }
    if (table.session?.isPendingPayment ?? false) {
      return (MeedColors.tableBusy, MeedColors.accent, t('tables.pendingPayment'), const Color(0xFF7D5A1E));
    }
    if (table.isOccupied) {
      return (MeedColors.tableBusy, MeedColors.accent, t('tables.busy'), const Color(0xFF7D5A1E));
    }
    return (MeedColors.tableFree, MeedColors.line, t('tables.free'), MeedColors.inkSoft);
  }
}
