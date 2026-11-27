import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/fitted_amount.dart';
import '../../core/widgets/option_lines.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/order_dto.dart';
import '../zones/zones_controller.dart';
import 'active_table_controller.dart';
import 'table_exit_listener.dart';

/// What has been sent to the kitchen at a table, asked of the server on every visit and never
/// kept: other handsets, the POS and the guests' own phones all add to it, and the kitchen moves
/// each dish along.
final tableBillProvider = FutureProvider.autoDispose.family<TableDetail, String>(
  (ref, floorItemId) => ref.watch(floorRepositoryProvider).table(floorItemId),
  retry: (_, _) => null,
);

/// Everything already sent to the kitchen at this table, round by round, with the running total.
///
/// A waiter can read it to a guest and say which dishes have reached the table. Voiding a line,
/// discounting it and taking the money all belong to the cashier at the POS.
class TableBillScreen extends ConsumerStatefulWidget {
  const TableBillScreen({super.key, required this.floorItemId});

  final String floorItemId;

  @override
  ConsumerState<TableBillScreen> createState() => _TableBillScreenState();
}

class _TableBillScreenState extends ConsumerState<TableBillScreen> {
  late final AppLifecycleListener _lifecycle;

  /// Lines being marked served, until the bill that shows it has arrived.
  final _serving = <String>{};

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(tableBillProvider(widget.floorItemId)),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final _ = await ref.refresh(tableBillProvider(widget.floorItemId).future);
    } on Object {
      // Shown by the screen itself, from the provider's state.
    }
  }

  Future<void> _serve(TableDetail detail, List<OrderLine> lines) async {
    final sessionId = detail.session?.sessionId;
    final ids = [for (final line in lines) line.orderItemId];
    if (sessionId == null || ids.any(_serving.contains)) return;
    final t = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    // Taken now, so the floor is still told if this screen is left while the request is out.
    final floor = ref.read(zonesProvider.notifier);
    setState(() => _serving.addAll(ids));

    ApiFailure? failure;
    try {
      await ref.read(floorRepositoryProvider).markServed(
            widget.floorItemId,
            sessionId: sessionId,
            orderItemIds: ids,
          );
    } on ApiFailure catch (error) {
      failure = error;
      messenger.showSnackBar(SnackBar(content: Text(t.failure(error))));
    }
    // With no signal nothing changed, and reloading would only replace the bill with an error.
    // Any other answer means the table may differ from what is on screen.
    if (!(failure?.isOffline ?? false)) {
      unawaited(floor.refreshAfterChange());
      if (mounted) await _reload();
    }
    if (mounted) setState(() => _serving.removeAll(ids));
  }

  /// A whole round at once is asked about first: it cannot be taken back.
  Future<void> _serveRound(TableDetail detail, int round, List<OrderLine> lines) async {
    final t = ref.read(stringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.format('bill.serveAllTitle', [round])),
        content: Text(t.format('bill.serveAllBody', [lines.length])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('bill.serveAll')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _serve(detail, lines);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final provider = tableBillProvider(widget.floorItemId);
    // The table screens read the same table (its round number), so they get the fresh copy too.
    ref.listen(provider, (previous, next) {
      final detail = next.value;
      if (detail != null && !next.isLoading && !next.hasError) {
        ref.read(activeTableProvider.notifier).adoptDetail(detail);
      }
    });
    final bill = ref.watch(provider);
    // From the bill itself, which may be read without holding the table; the held table's label
    // covers the moment before it arrives.
    final held = ref.watch(
      activeTableProvider.select(
        (s) => s.floorItemId == widget.floorItemId ? s.tableLabel : '',
      ),
    );
    final label = bill.value?.label ?? held;
    // After a failed reload the older bill is not shown: it would read as the current one.
    final failed = bill.hasError && !bill.isLoading;
    final order = failed ? null : bill.value?.order;

    final Widget body;
    if (failed) {
      final error = bill.error!;
      body = ErrorView(
        failure: error is ApiFailure
            ? error
            : ApiFailure(code: 'UNKNOWN', message: error.toString()),
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(provider),
      );
    } else if (!bill.hasValue || bill.hasError) {
      // Still loading — including a retry, which must not fall back to the older bill meanwhile.
      body = const LoadingView();
    } else {
      body = Column(
        children: [
          if (bill.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: order == null || order.activeLines.isEmpty
                  ? CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                            message: t('bill.empty'),
                            icon: Icons.receipt_long_outlined,
                          ),
                        ),
                      ],
                    )
                  : _Bill(
                      order: order,
                      t: t,
                      serving: _serving,
                      onServe: (line) => _serve(bill.value!, [line]),
                      onServeRound: (round, lines) => _serveRound(bill.value!, round, lines),
                    ),
            ),
          ),
        ],
      );
    }

    return TableExitListener(
      floorItemId: widget.floorItemId,
      child: Scaffold(
        appBar: AppBar(title: Text('${t('bill.title')} · $label')),
        body: body,
        bottomNavigationBar: order == null ? null : _PayAtPosBar(t: t),
      ),
    );
  }
}

class _PayAtPosBar extends StatelessWidget {
  const _PayAtPosBar({required this.t});

  final AppStrings t;

  @override
  Widget build(BuildContext context) => Container(
        // No SafeArea around the bar: its background runs to the bottom edge, and only what is
        // in it is lifted clear of the home indicator.
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(
          color: MeedColors.card,
          border: Border(top: BorderSide(color: MeedColors.line)),
        ),
        child: Row(
          children: [
            const Icon(Icons.point_of_sale_rounded, size: 18, color: MeedColors.inkSoft),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t('bill.payAtPos'),
                style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
              ),
            ),
          ],
        ),
      );
}

class _Bill extends StatelessWidget {
  const _Bill({
    required this.order,
    required this.t,
    required this.serving,
    required this.onServe,
    required this.onServeRound,
  });

  final TableOrder order;
  final AppStrings t;
  final Set<String> serving;
  final ValueChanged<OrderLine> onServe;
  final void Function(int round, List<OrderLine> lines) onServeRound;

  Widget _roundHeader(int round, List<OrderLine> lines) {
    final waiting = lines.where((line) => line.canBeServed).toList();
    final busy = waiting.any((line) => serving.contains(line.orderItemId));
    return ConstrainedBox(
      // As tall with the button as without it, so rounds do not shift as dishes are served.
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${t('bill.round')} $round',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (waiting.isNotEmpty)
            TextButton.icon(
              onPressed: busy ? null : () => onServeRound(round, waiting),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: Text(t('bill.serveAll')),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rounds = order.linesByRound;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          '${t('bill.orderNumber')} ${order.orderNumber}',
          style: const TextStyle(fontSize: 14, color: MeedColors.inkSoft),
        ),
        const SizedBox(height: 6),
        for (final entry in rounds.entries) ...[
          _roundHeader(entry.key, entry.value),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _LineRow(
                    line: entry.value[i],
                    t: t,
                    busy: serving.contains(entry.value[i].orderItemId),
                    onServe: () => onServe(entry.value[i]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _TotalRow(label: t('bill.subtotal'), value: t.money(order.subtotal)),
                if (order.discountAmount > 0)
                  _TotalRow(
                    label: t('bill.discount'),
                    value: '-${t.money(order.discountAmount)}',
                  ),
                if (order.serviceChargeAmount > 0)
                  _TotalRow(
                    label: t('bill.serviceCharge'),
                    value: t.money(order.serviceChargeAmount),
                  ),
                if (order.taxAmount > 0)
                  _TotalRow(label: t('bill.tax'), value: t.money(order.taxAmount)),
                const Divider(height: 20),
                _TotalRow(
                  label: t('bill.total'),
                  value: t.money(order.totalAmount),
                  emphasised: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.t, required this.busy, required this.onServe});

  final OrderLine line;
  final AppStrings t;
  final bool busy;
  final VoidCallback onServe;

  /// The quantity's column, which everything under the dish's name is lined up past.
  static const _quantityWidth = 34.0;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _quantityWidth,
                  child: Text(
                    '${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)}×',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                      ),
                      if (line.skuName.isNotEmpty)
                        Text(
                          line.skuName,
                          style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
                        ),
                      if (line.options.isNotEmpty)
                        OptionLines(
                          options: [
                            for (final o in line.options)
                              (name: o.optionName, quantity: o.quantity, price: o.priceAdjustment),
                          ],
                          t: t,
                        ),
                      if (line.note != null && line.note!.isNotEmpty)
                        Text(
                          line.note!,
                          style: const TextStyle(fontSize: 13, color: MeedColors.accent),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: FittedAmount(
                    t.money(line.lineTotal),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (line.kitchenStatus != null)
              Padding(
                padding: const EdgeInsets.only(left: _quantityWidth, top: 4),
                child: SizedBox(
                  width: double.infinity,
                  // The button ends under the price, and drops below the badge where there is
                  // no room beside it.
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      _KitchenBadge(status: line.kitchenStatus!, t: t),
                      if (line.canBeServed)
                        _ServeButton(label: t('bill.serve'), busy: busy, onPressed: onServe),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ServeButton extends StatelessWidget {
  const _ServeButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        // The app's buttons are full width by default; this one sits inside a row.
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(88, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check_rounded, size: 18),
        label: Text(label),
      );
}

class _KitchenBadge extends StatelessWidget {
  const _KitchenBadge({required this.status, required this.t});

  final String status;
  final AppStrings t;

  /// The stage in words; a status this app does not know is shown as the server sent it.
  String get _label {
    final key = 'kitchen.${status.toLowerCase()}';
    final label = t(key);
    return label == key ? status : label;
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status.toUpperCase()) {
      'READY' => (
          Theme.of(context).colorScheme.primaryTint,
          Theme.of(context).colorScheme.primaryStrong,
        ),
      'SERVED' => (MeedColors.tableFree, MeedColors.inkSoft),
      'SENT' || 'PREPARING' => (MeedColors.tableBusy, const Color(0xFF7D5A1E)),
      'CANCELLED' => (MeedColors.tableLocked, MeedColors.danger),
      _ => (MeedColors.surface, MeedColors.inkSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(
        _label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.emphasised = false});

  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: emphasised ? 17 : 15,
                  fontWeight: emphasised ? FontWeight.w800 : FontWeight.w500,
                  color: emphasised ? MeedColors.ink : MeedColors.inkSoft,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: FittedAmount(
                value,
                style: TextStyle(
                  fontSize: emphasised ? 19 : 15,
                  fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
