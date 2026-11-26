import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/order_dto.dart';
import 'active_table_controller.dart';
import 'table_exit_listener.dart';

/// Everything already sent to the kitchen at this table, round by round, with the running total.
///
/// Read-only on purpose. A waiter can see the bill and read it to a guest; voiding a line,
/// discounting it and taking the money all belong to the cashier at the POS.
class TableBillScreen extends ConsumerStatefulWidget {
  const TableBillScreen({super.key, required this.floorItemId});

  final String floorItemId;

  @override
  ConsumerState<TableBillScreen> createState() => _TableBillScreenState();
}

class _TableBillScreenState extends ConsumerState<TableBillScreen> {
  @override
  void initState() {
    super.initState();
    // The totals may have moved since the floor was loaded — the cashier may have discounted the
    // bill, or a QR customer at the same table may have added a round.
    Future.microtask(() => ref.read(activeTableProvider.notifier).refreshDetail());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final table = ref.watch(activeTableProvider);
    final order = table.detail?.order;

    return TableExitListener(
      floorItemId: widget.floorItemId,
      child: Scaffold(
        appBar: AppBar(title: Text('${t('bill.title')} · ${table.tableLabel}')),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.read(activeTableProvider.notifier).refreshDetail(),
            child: order == null || order.activeLines.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: EmptyView(
                          message: t('bill.empty'),
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                    ],
                  )
                : _Bill(order: order, t: t),
          ),
        ),
        bottomNavigationBar: order == null
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                ),
              ),
      ),
    );
  }
}

class _Bill extends StatelessWidget {
  const _Bill({required this.order, required this.t});

  final TableOrder order;
  final AppStrings t;

  @override
  Widget build(BuildContext context) {
    final rounds = order.linesByRound;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          '${t('bill.orderNumber')} ${order.orderNumber}',
          style: const TextStyle(fontSize: 14, color: MeedColors.inkSoft),
        ),
        const SizedBox(height: 14),
        for (final entry in rounds.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${t('bill.round')} ${entry.key}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _LineRow(line: entry.value[i], t: t),
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
  const _LineRow({required this.line, required this.t});

  final OrderLine line;
  final AppStrings t;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
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
                  if (line.skuName.isNotEmpty || line.options.isNotEmpty)
                    Text(
                      [
                        if (line.skuName.isNotEmpty) line.skuName,
                        if (line.options.isNotEmpty) line.optionsLabel,
                      ].join(' • '),
                      style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
                    ),
                  if (line.note != null && line.note!.isNotEmpty)
                    Text(
                      line.note!,
                      style: const TextStyle(fontSize: 13, color: MeedColors.accent),
                    ),
                  if (line.kitchenStatus != null) ...[
                    const SizedBox(height: 4),
                    _KitchenBadge(status: line.kitchenStatus!),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              t.money(line.lineTotal),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _KitchenBadge extends StatelessWidget {
  const _KitchenBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status.toUpperCase()) {
      'READY' => (
          Theme.of(context).colorScheme.primaryTint,
          Theme.of(context).colorScheme.primaryStrong,
        ),
      'SERVED' => (MeedColors.tableFree, MeedColors.inkSoft),
      'PREPARING' => (MeedColors.tableBusy, const Color(0xFF7D5A1E)),
      'CANCELLED' => (MeedColors.tableLocked, MeedColors.danger),
      _ => (MeedColors.surface, MeedColors.inkSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(
        status,
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
            Text(
              value,
              style: TextStyle(
                fontSize: emphasised ? 19 : 15,
                fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}
