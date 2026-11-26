import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/floor_dto.dart';
import '../zones/zones_controller.dart';
import 'table_tile.dart';

/// Picks a free table to move or merge into: nobody seated, in service and not held by another
/// handset. The server checks again when the change is made.
Future<FloorTable?> showTablePicker(BuildContext context, {required String title}) =>
    showModalBottomSheet<FloorTable>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.8,
        child: _TablePicker(title: title),
      ),
    );

class _TablePicker extends ConsumerStatefulWidget {
  const _TablePicker({required this.title});

  final String title;

  @override
  ConsumerState<_TablePicker> createState() => _TablePickerState();
}

class _TablePickerState extends ConsumerState<_TablePicker> {
  @override
  void initState() {
    super.initState();
    // Which tables are free is exactly what the floor on screen may be behind on.
    Future.microtask(() {
      if (mounted) unawaited(ref.read(zonesProvider.notifier).refresh());
    });
  }

  static bool _isFree(FloorTable table) =>
      table.session == null && !table.isOutOfService && !table.isHeldByOther;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final floor = ref.watch(zonesProvider).value;
    final refreshing = floor?.refreshing ?? false;
    final zones = [
      for (final zone in floor?.zones ?? const <FloorZone>[])
        if (zone.tables.any(_isFree)) (zone: zone, tables: zone.tables.where(_isFree).toList()),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: 2,
          child: refreshing ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Expanded(
          child: zones.isEmpty
              ? EmptyView(message: t('sheet.noFreeTable'), icon: Icons.table_bar_outlined)
              : CustomScrollView(
                  slivers: [
                    for (final entry in zones) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            entry.zone.zoneName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: MeedColors.inkSoft,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                          ),
                          itemCount: entry.tables.length,
                          itemBuilder: (context, index) => TableTile(
                            floorItemId: entry.tables[index].floorItemId,
                            onTap: () => Navigator.of(context).pop(entry.tables[index]),
                          ),
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
