import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/floor_dto.dart';
import '../../router/app_router.dart';
import '../bootstrap/session_controller.dart';
import 'zones_controller.dart';

/// The first screen of a shift: pick a zone.
class ZonesScreen extends ConsumerWidget {
  const ZonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final zones = ref.watch(zonesProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('zones.title')),
        actions: [
          IconButton(
            tooltip: t('settings.title'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => AppRoutes.goSettings(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (session.staffName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 18, color: MeedColors.inkSoft),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      session.staffName!,
                      style: const TextStyle(color: MeedColors.inkSoft, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(zonesProvider.notifier).refresh(),
              child: switch (zones) {
                AsyncError(:final error) => ErrorView(
                    failure: error is ApiFailure
                        ? error
                        : ApiFailure(code: 'UNKNOWN', message: error.toString()),
                    retryLabel: t('common.retry'),
                    onRetry: () => ref.read(zonesProvider.notifier).refresh(),
                  ),
                AsyncData(:final value) when value.isEmpty =>
                  EmptyView(message: t('zones.empty'), icon: Icons.table_restaurant_outlined),
                AsyncData(:final value) => _ZoneList(zones: value, t: t),
                _ => const LoadingView(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneList extends StatelessWidget {
  const _ZoneList({required this.zones, required this.t});

  final List<FloorZone> zones;
  final AppStrings t;

  @override
  Widget build(BuildContext context) => ListView.separated(
        // The list runs to the bottom edge, under the home indicator; the inset is added to the
        // scroll padding so the last card can still be scrolled clear of it.
        padding: EdgeInsets.fromLTRB(16, 16, 16, 28 + MediaQuery.paddingOf(context).bottom),
        itemCount: zones.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final zone = zones[index];
          final mine = zone.tables.where((table) => table.isHeldByMe).length;
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => AppRoutes.goZone(context, zone.zoneId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorFromHex(zone.colorHex) ?? Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            zone.zoneName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${zone.tableCount} ${t('zones.tables')} · '
                            '${zone.freeCount} ${t('zones.free')} · '
                            '${zone.occupiedCount} ${t('zones.busy')}',
                            style: const TextStyle(fontSize: 14, color: MeedColors.inkSoft),
                          ),
                          if (mine > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              '$mine · ${t('tables.heldByMe')}',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: MeedColors.inkSoft),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
