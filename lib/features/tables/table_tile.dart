import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dto/floor_dto.dart';
import '../zones/zones_controller.dart';

/// The ring colour for each stage of a table's food.
Color tableRingColor(TableFoodStatus status) => switch (status) {
      TableFoodStatus.free => MeedColors.ringFree,
      TableFoodStatus.notOrdered => MeedColors.ringNotOrdered,
      TableFoodStatus.waiting => MeedColors.ringWaiting,
      TableFoodStatus.served => MeedColors.ringServed,
    };

/// The string key naming each stage, shared by the legend and the screen reader.
String tableStatusKey(TableFoodStatus status) => switch (status) {
      TableFoodStatus.free => 'tables.free',
      TableFoodStatus.notOrdered => 'tables.notOrdered',
      TableFoodStatus.waiting => 'tables.waiting',
      TableFoodStatus.served => 'tables.served',
    };

/// How thick a table's ring is, in every state.
const double tableRingWidth = 4;

/// One table: its name, how many it seats, and a ring saying how far along its food is. A corner
/// icon covers what the ring cannot — who holds the table, and a bill open at the POS.
///
/// Watches only its own table, so a refresh repaints just the tables that changed.
class TableTile extends ConsumerWidget {
  const TableTile({super.key, required this.floorItemId, required this.onTap});

  final String floorItemId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final table = ref.watch(zonesProvider.select((s) => s.value?.table(floorItemId)));
    if (table == null) return const SizedBox.shrink();
    final t = ref.watch(stringsProvider);

    final disabled = table.isOutOfService;
    final pendingPayment = table.session?.isPendingPayment ?? false;
    final description = [
      table.label,
      if (disabled) t('tables.outOfService') else t(tableStatusKey(table.foodStatus)),
      if (table.isHeldByMe) t('tables.heldByMe'),
      if (table.isHeldByOther) '${t('tables.heldBy')} ${table.claim!.holder.staffName}',
      if (pendingPayment) t('tables.pendingPayment'),
    ].join(', ');

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: disabled ? MeedColors.line : tableRingColor(table.foodStatus),
        width: tableRingWidth,
      ),
    );
    final ink = disabled ? MeedColors.inkSoft : MeedColors.tableText;

    return Semantics(
      button: !disabled,
      label: description,
      excludeSemantics: true,
      onTap: disabled ? null : onTap,
      child: Material(
        color: disabled ? MeedColors.tableDisabled : MeedColors.card,
        shape: shape,
        child: InkWell(
          onTap: disabled ? null : onTap,
          customBorder: shape,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        table.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
                      ),
                      if (table.capacity != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_rounded, size: 19, color: ink),
                            const SizedBox(width: 4),
                            Text(
                              '${table.capacity}',
                              style:
                                  TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    if (pendingPayment)
                      const Icon(Icons.receipt_long_rounded, size: 16, color: MeedColors.accent),
                    if (table.isHeldByMe)
                      Icon(Icons.edit_rounded,
                          size: 16, color: Theme.of(context).colorScheme.primary),
                    if (table.isHeldByOther)
                      const Icon(Icons.lock_rounded, size: 16, color: MeedColors.danger),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
