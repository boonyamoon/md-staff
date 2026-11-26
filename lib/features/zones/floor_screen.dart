import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/stale_banner.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/floor_dto.dart';
import '../../router/app_router.dart';
import '../bootstrap/session_controller.dart';
import '../menu/menu_catalog_controller.dart';
import '../tables/active_table_controller.dart';
import '../tables/table_action_sheet.dart';
import '../tables/table_tile.dart';
import 'zones_controller.dart';

/// The first screen of a shift: a tab per zone, its tables three across. Tapping a table brings up
/// its menu — order, bill, guests, QR, cancel, move and merge.
class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({super.key});

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    // The menu is fetched from here, not when the first table is opened, so that it is already on
    // the handset when the signal drops at that table.
    ref.listenManual(menuCatalogProvider, (_, _) {});
  }

  Future<void> _openTable(String floorItemId) async {
    // A second tap before the menu is up would stack a second one.
    if (_opening) return;
    _opening = true;
    try {
      final result = await showTableSheet(context, floorItemId: floorItemId);
      if (!mounted || result == null) return;
      final message = result.message;
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      switch (result.next) {
        case TableSheetNext.order:
          AppRoutes.goMenu(context, floorItemId);
        case TableSheetNext.bill:
          AppRoutes.goBill(context, floorItemId);
        case TableSheetNext.stay:
          break;
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final staffName = ref.watch(sessionProvider.select((s) => s.staffName));
    final view = ref.watch(zonesProvider.select(_FloorView.of));

    return Scaffold(
      // White behind the tables, so that even the pale ring of a free one stands out.
      backgroundColor: MeedColors.card,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tight line heights: both lines must fit the bar at the largest text size.
            Text(t('floor.title'), style: const TextStyle(height: 1.2)),
            if (staffName != null && staffName.isNotEmpty)
              Text(
                staffName,
                style: const TextStyle(fontSize: 12.5, height: 1.2, color: MeedColors.inkSoft),
              ),
          ],
        ),
        actions: [
          const _RefreshButton(),
          IconButton(
            tooltip: t('settings.title'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => AppRoutes.goSettings(context),
          ),
        ],
      ),
      body: switch (view) {
        _FloorView(error: final error?) => ErrorView(
            failure: error is ApiFailure
                ? error
                : ApiFailure(code: 'UNKNOWN', message: error.toString()),
            retryLabel: t('common.retry'),
            onRetry: () => ref.read(zonesProvider.notifier).refresh(),
          ),
        _FloorView(loaded: false) => const LoadingView(),
        _FloorView(zones: []) => _PullToRefresh(
            message: t('zones.empty'),
            icon: Icons.table_restaurant_outlined,
          ),
        _ => _ZoneTabs(zones: view.zones, onOpen: _openTable),
      },
    );
  }
}

/// What the frame of the screen depends on: which zones there are, not what is on their tables —
/// so a refresh that only changes tables leaves the tabs alone.
@immutable
class _FloorView {
  const _FloorView({required this.loaded, required this.zones, required this.key, this.error});

  factory _FloorView.of(AsyncValue<FloorState> floor) {
    final value = floor.value;
    final loaded = value?.fetchedAt != null;
    final zones = value?.zones ?? const <FloorZone>[];
    return _FloorView(
      loaded: loaded,
      zones: [for (final zone in zones) (id: zone.zoneId, name: zone.zoneName)],
      key: [for (final zone in zones) '${zone.zoneId}\u0000${zone.zoneName}'].join('\u0000'),
      error: !loaded && floor.hasError && !floor.isLoading ? floor.error : null,
    );
  }

  final bool loaded;
  final List<({String id, String name})> zones;
  final String key;

  /// Set only when there is no floor at all to show.
  final Object? error;

  @override
  bool operator ==(Object other) =>
      other is _FloorView && other.loaded == loaded && other.key == key && other.error == error;

  @override
  int get hashCode => Object.hash(loaded, key, error);
}

class _ZoneTabs extends StatelessWidget {
  const _ZoneTabs({required this.zones, required this.onOpen});

  final List<({String id, String name})> zones;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: zones.length,
        child: Column(
          children: [
            Material(
              color: MeedColors.card,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: MeedColors.ink,
                  unselectedLabelColor: MeedColors.inkSoft,
                  labelStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [for (final zone in zones) Tab(text: zone.name)],
                ),
              ),
            ),
            const Divider(height: 1),
            const _BusyLine(),
            const _Legend(),
            const _FloorStaleBanner(),
            Expanded(
              child: TabBarView(
                children: [
                  for (final zone in zones)
                    _ZoneGrid(key: ValueKey(zone.id), zoneId: zone.id, onOpen: onOpen),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ZoneGrid extends ConsumerWidget {
  const _ZoneGrid({super.key, required this.zoneId, required this.onOpen});

  final String zoneId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The ids as one string, which compares by value: the grid rebuilds only when tables are
    // added, removed or reordered. Each tile watches its own table for everything else.
    final ids = ref.watch(
      zonesProvider.select(
        (s) => s.value?.zone(zoneId)?.tables.map((t) => t.floorItemId).join(',') ?? '',
      ),
    );
    if (ids.isEmpty) {
      final t = ref.watch(stringsProvider);
      return _PullToRefresh(message: t('tables.empty'), icon: Icons.table_bar_outlined);
    }
    final tables = ids.split(',');

    return RefreshIndicator(
      onRefresh: () => ref.read(zonesProvider.notifier).refresh(),
      child: GridView.builder(
        // Remembers where each zone was scrolled to while another tab is shown.
        key: PageStorageKey<String>(zoneId),
        physics: const AlwaysScrollableScrollPhysics(),
        // The grid runs to the bottom edge, under the home indicator; the inset is added to the
        // scroll padding so the last row can still be scrolled clear of it.
        padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + MediaQuery.paddingOf(context).bottom),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) => TableTile(
          key: ValueKey(tables[index]),
          floorItemId: tables[index],
          onTap: () => onOpen(tables[index]),
        ),
      ),
    );
  }
}

/// An empty message that can still be pulled down to ask again.
class _PullToRefresh extends ConsumerWidget {
  const _PullToRefresh({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
        onRefresh: () => ref.read(zonesProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyView(message: message, icon: icon),
            ),
          ],
        ),
      );
}

class _RefreshButton extends ConsumerWidget {
  const _RefreshButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshing = ref.watch(
      zonesProvider.select((s) => s.isLoading || (s.value?.refreshing ?? false)),
    );
    return IconButton(
      tooltip: ref.watch(stringsProvider)('common.refresh'),
      icon: const Icon(Icons.refresh_rounded),
      onPressed: refreshing ? null : () => ref.read(zonesProvider.notifier).refresh(),
    );
  }
}

/// A thin progress line while the floor is being fetched or a table is being opened. It keeps its
/// height either way, so the grid does not jump.
class _BusyLine extends ConsumerWidget {
  const _BusyLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshing = ref.watch(zonesProvider.select((s) => s.value?.refreshing ?? false));
    final opening = ref.watch(activeTableProvider.select((s) => s.loading));
    return SizedBox(
      height: 2,
      child: refreshing || opening ? const LinearProgressIndicator(minHeight: 2) : null,
    );
  }
}

class _Legend extends ConsumerWidget {
  const _Legend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          for (final status in TableFoodStatus.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: tableRingColor(status), width: 3),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  t(tableStatusKey(status)),
                  style: const TextStyle(fontSize: 12.5, color: MeedColors.inkSoft),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FloorStaleBanner extends ConsumerWidget {
  const _FloorStaleBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stale = ref.watch(
      zonesProvider.select((s) => (s.value?.failure, s.value?.fetchedAt)),
    );
    final failure = stale.$1;
    if (failure == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: StaleBanner(failure: failure, fetchedAt: stale.$2),
    );
  }
}
