import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/stale_banner.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/floor_dto.dart';
import '../../data/repositories/floor_repository.dart';
import '../bootstrap/session_controller.dart';
import '../zones/zones_controller.dart';
import 'active_table_controller.dart';
import 'table_actions.dart';
import 'table_dialogs.dart';
import 'table_picker_sheet.dart';
import 'table_sheet_model.dart';
import 'table_tile.dart';
import 'take_over_sheet.dart';

/// Where to go once the table menu has closed.
enum TableSheetNext {
  stay,

  /// To the menu. The table's claim is held.
  order,
  bill,
}

class TableSheetResult {
  const TableSheetResult({this.next = TableSheetNext.stay, this.message});

  final TableSheetNext next;

  /// Something to say on the floor, once this menu is out of the way.
  final String? message;
}

/// The menu of one table, from the bottom of the floor.
Future<TableSheetResult?> showTableSheet(BuildContext context, {required String floorItemId}) =>
    showModalBottomSheet<TableSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TableActionSheet(floorItemId: floorItemId),
    );

/// Looking costs nothing: the table is claimed only when something on it is about to change, and
/// given back as soon as that is done — except on the way to the menu, which needs it.
class TableActionSheet extends ConsumerStatefulWidget {
  const TableActionSheet({super.key, required this.floorItemId});

  final String floorItemId;

  @override
  ConsumerState<TableActionSheet> createState() => _TableActionSheetState();
}

class _TableActionSheetState extends ConsumerState<TableActionSheet> {
  /// Read through the container, not `ref`: a change under way must still be able to give the
  /// table back after this menu has been swiped away.
  late final ProviderContainer _providers;
  /// A press is being handled, its dialogs included.
  bool _busy = false;

  /// The server is being waited on — what the progress line shows, so it does not run behind a
  /// dialog that is waiting for the waiter.
  bool _working = false;
  String? _note;
  bool _noteIsError = false;

  String get _id => widget.floorItemId;
  AppStrings get _t => _providers.read(stringsProvider);

  @override
  void initState() {
    super.initState();
    _providers = ProviderScope.containerOf(context, listen: false);
  }

  void _setWorking(bool value) {
    if (mounted && _working != value) setState(() => _working = value);
  }

  void _say(String message, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      _note = message;
      _noteIsError = error;
    });
  }

  /// Runs one press at a time, and closes the menu when [action] says where to go next.
  Future<void> _run(Future<TableSheetResult?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    TableSheetResult? result;
    try {
      result = await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  /// Takes the table, asking for a manager PIN if another handset has it. Returns the lease, or
  /// null — having said why — when the table could not be taken.
  Future<String?> _claim() async {
    final controller = _providers.read(activeTableProvider.notifier);
    final floor = _providers.read(zonesProvider.notifier);
    _setWorking(true);
    final opened = await controller.open(_id);
    _setWorking(false);
    if (!mounted) {
      // Swiped away while claiming: nobody is left to use the table.
      await controller.close();
      return null;
    }
    final state = _providers.read(activeTableProvider);
    if (opened) return state.claim?.leaseToken;

    final failure = state.failure;
    if (failure?.code == 'TABLE_CLAIM_HELD') {
      // The floor on screen may have been behind, so it is fetched again.
      unawaited(floor.refresh());
      final table = _providers.read(zonesProvider).value?.table(_id);
      final taken = table == null
          ? false
          : await showTakeOverSheet(context, table: table, failure: failure);
      controller.acknowledgeFailure();
      if (taken != true) return null;
      if (!mounted) {
        await controller.close();
        return null;
      }
      return _providers.read(activeTableProvider).claim?.leaseToken;
    }
    if (state.exitReason == TableExitReason.pendingPayment) {
      unawaited(floor.refresh());
      controller.acknowledgeExit();
      _say(_t('error.pendingPayment'));
      return null;
    }
    if (failure != null) {
      controller.acknowledgeFailure();
      _say(failure.isOffline ? _t('error.needOnline') : _t.failure(failure));
    }
    return null;
  }

  /// Claims the table, makes [change], gives the table back, and brings the floor and this menu up
  /// to date. Returns whether the change was made.
  Future<bool> _change(
    Future<void> Function(FloorRepository tables, String lease) change,
  ) async {
    final controller = _providers.read(activeTableProvider.notifier);
    final floor = _providers.read(zonesProvider.notifier);
    final tables = _providers.read(floorRepositoryProvider);
    final lease = await _claim();
    if (lease == null) return false;
    _setWorking(true);
    try {
      await change(tables, lease);
      return true;
    } on ApiFailure catch (failure) {
      _say(_t.failure(failure));
      return false;
    } finally {
      await controller.close();
      _setWorking(false);
      unawaited(floor.refreshAfterChange());
      if (mounted) ref.invalidate(tableSheetProvider(_id));
    }
  }

  Future<void> _once(String intent, Future<void> Function(String key) send) =>
      _providers.read(idempotencyKeysProvider).run(intent, send);

  // ── The buttons ──

  Future<TableSheetResult?> _order(TableSheetView view) async {
    // Asked on the way in, with the guests in front of the waiter: left to the cart screen alone,
    // the count is easily sent as 1. The first round saves it, which is what opens the table.
    int? guests;
    if (!view.isOpen) {
      guests = await showGuestCountDialog(
        context,
        title: _t.format('sheet.guestsFor', [view.label]),
        initial: 1,
      );
      if (guests == null || !mounted) return null;
    }
    if (await _claim() == null) return null;
    // Unless the table was seated meanwhile: that party's own count stands.
    if (guests != null && _providers.read(activeTableProvider).detail?.session == null) {
      _providers.read(activeTableProvider.notifier).setGuestCount(guests);
    }
    return const TableSheetResult(next: TableSheetNext.order);
  }

  Future<void> _open(FloorRepository tables, String lease, int guests) => _once(
        'open:$_id:$guests',
        (key) => tables.openTable(_id,
            leaseToken: lease, idempotencyKey: key, guestCount: guests),
      );

  Future<TableSheetResult?> _guests(TableSheetView view) async {
    final count = await showGuestCountDialog(
      context,
      title: view.isOpen ? _t('sheet.guests') : _t.format('sheet.openTitle', [view.label]),
      initial: view.guestCount ?? 1,
    );
    if (count == null || !mounted) return null;
    final session = view.sessionId;
    if (session != null && count == view.guestCount) return null;
    final saved = await _change(
      (tables, lease) => session == null
          ? _open(tables, lease, count)
          : tables.setGuestCount(_id, leaseToken: lease, sessionId: session, guestCount: count),
    );
    if (saved) _say(_t('sheet.guestsSaved'), error: false);
    return null;
  }

  Future<TableSheetResult?> _qr(TableSheetView view) async {
    int? guests;
    if (!view.isOpen) {
      // A guest can only order for a table that is open, so this opens it — say so first.
      guests = await showGuestCountDialog(context, title: _t('sheet.openAndQr'), initial: 1);
      if (guests == null || !mounted) return null;
    }
    TableQr? qr;
    await _change((tables, lease) async {
      if (guests != null) await _open(tables, lease, guests);
      qr = await tables.tableQr(_id, leaseToken: lease);
    });
    final code = qr;
    if (code != null && mounted) await showTableQr(context, label: view.title, qr: code);
    return null;
  }

  Future<TableSheetResult?> _cancel(TableSheetView view) async {
    final confirmed = await showTableConfirm(
      context,
      t: _t,
      title: _t.format('sheet.cancelTitle', [view.title]),
      body: _t('sheet.cancelBody'),
      destructive: true,
    );
    final session = view.sessionId;
    if (!confirmed || session == null || !mounted) return null;
    final done = _t.format('sheet.cancelled', [view.title]);
    final cancelled = await _change(
      (tables, lease) => _once(
        'cancel:$session',
        (key) => tables.cancelTable(_id,
            leaseToken: lease, idempotencyKey: key, sessionId: session),
      ),
    );
    return cancelled ? TableSheetResult(message: done) : null;
  }

  Future<TableSheetResult?> _transfer(TableSheetView view) async {
    final to = await showTablePicker(
      context,
      title: _t.format('sheet.transferPick', [view.label]),
    );
    final session = view.sessionId;
    if (to == null || session == null || !mounted) return null;
    final confirmed = await showTableConfirm(
      context,
      t: _t,
      title: _t.format('sheet.transferConfirm', [view.label, to.label]),
    );
    if (!confirmed || !mounted) return null;
    final done = _t.format('sheet.transferred', [to.label]);
    final moved = await _change(
      (tables, lease) => _once(
        'transfer:$session:$_id:${to.floorItemId}',
        (key) => tables.transferTable(_id,
            leaseToken: lease,
            idempotencyKey: key,
            sessionId: session,
            destinationId: to.floorItemId),
      ),
    );
    return moved ? TableSheetResult(message: done) : null;
  }

  Future<TableSheetResult?> _merge(TableSheetView view) async {
    final other = await showTablePicker(
      context,
      title: _t.format('sheet.mergePick', [view.title]),
    );
    final session = view.sessionId;
    if (other == null || session == null || !mounted) return null;
    final confirmed = await showTableConfirm(
      context,
      t: _t,
      title: _t.format('sheet.mergeConfirm', [view.label, other.label]),
    );
    if (!confirmed || !mounted) return null;
    final merged = await _change(
      (tables, lease) => _once(
        'merge:$session:${other.floorItemId}',
        (key) => tables.mergeTable(_id,
            leaseToken: lease,
            idempotencyKey: key,
            sessionId: session,
            otherId: other.floorItemId),
      ),
    );
    if (merged) _say(_t.format('sheet.merged', [other.label]), error: false);
    return null;
  }

  Future<TableSheetResult?> _unmerge(TableSheetView view) async {
    final choices = view.splittable;
    if (choices.isEmpty) return null;
    final target = choices.length == 1
        ? choices.single
        : await showDialog<TableRef>(
            context: context,
            builder: (context) => SimpleDialog(
              title: Text(_t('sheet.unmergePick')),
              children: [
                for (final table in choices)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(table),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(table.label, style: const TextStyle(fontSize: 17)),
                    ),
                  ),
              ],
            ),
          );
    final session = view.sessionId;
    if (target == null || session == null || !mounted) return null;
    final confirmed = await showTableConfirm(
      context,
      t: _t,
      title: _t.format('sheet.unmergeConfirm', [target.label]),
    );
    if (!confirmed || !mounted) return null;
    final done = _t.format('sheet.unmerged', [target.label]);
    final split = await _change(
      (tables, lease) => _once(
        'unmerge:$session:${target.floorItemId}',
        (key) => tables.unmergeTable(_id,
            leaseToken: lease,
            idempotencyKey: key,
            sessionId: session,
            otherId: target.floorItemId),
      ),
    );
    if (!split) return null;
    // Splitting off the table this menu is about leaves it free: nothing more to show.
    if (target.floorItemId == _id) return TableSheetResult(message: done);
    _say(done, error: false);
    return null;
  }

  void _press(TableMenuAction action, TableSheetView view, {required bool offline}) {
    if (_busy) return;
    final reason = blockedReason(action, view, offline: offline);
    if (reason != null) {
      _say(_t(reason));
      return;
    }
    unawaited(_run(() async => switch (action) {
          TableMenuAction.order => await _order(view),
          TableMenuAction.bill => const TableSheetResult(next: TableSheetNext.bill),
          TableMenuAction.guests => await _guests(view),
          TableMenuAction.qr => await _qr(view),
          TableMenuAction.cancel => await _cancel(view),
          TableMenuAction.transfer => await _transfer(view),
          TableMenuAction.merge => await _merge(view),
          TableMenuAction.unmerge => await _unmerge(view),
        }));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final floor = ref.watch(zonesProvider.select((s) => s.value?.table(_id)));
    final floorAt = ref.watch(zonesProvider.select((s) => s.value?.fetchedAt));
    final detail = ref.watch(tableSheetProvider(_id));
    final error = detail.hasError && !detail.isLoading ? detail.error : null;
    final failure = switch (error) {
      null => null,
      final ApiFailure failure => failure,
      _ => ApiFailure(code: 'UNKNOWN', message: error.toString()),
    };
    final offline = failure?.isOffline ?? false;
    final view = TableSheetView.of(
      _id,
      floor: floor,
      detail: detail.hasError ? null : detail.value,
    );
    // `exists` first: asking would start the request, and the theme has already done so.
    final currency = ref.exists(configProvider)
        ? ref.read(configProvider).value?.branch.currency ?? 'THB'
        : 'THB';

    Widget card(TableMenuAction action, IconData icon, String label, {Color? color}) =>
        Expanded(
          child: _ActionCard(
            icon: icon,
            label: label,
            color: color,
            enabled: blockedReason(action, view, offline: offline) == null,
            onTap: () => _press(action, view, offline: offline),
          ),
        );

    final orderEnabled = blockedReason(TableMenuAction.order, view, offline: offline) == null;
    final billEnabled = blockedReason(TableMenuAction.bill, view, offline: offline) == null;

    return PopScope(
      // Back waits for a change under way, so its outcome is not lost unseen.
      canPop: !_busy,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(view: view, t: t, now: ref.watch(clockProvider)()),
            SizedBox(
              height: 10,
              child: Center(
                child: _working || detail.isLoading
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
            ),
            if (failure != null)
              offline
                  ? StaleBanner(failure: failure, fetchedAt: floorAt)
                  : NoticeBanner(message: t.failure(failure), tone: NoticeTone.warning),
            if (view.heldBy != null)
              NoticeBanner(
                message: t.format('sheet.heldNote', [view.heldBy!]),
                tone: NoticeTone.warning,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusPill(
                    view: view,
                    t: t,
                    onOrder: !view.hasDishes && orderEnabled
                        ? () => _press(TableMenuAction.order, view, offline: offline)
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      card(
                        TableMenuAction.guests,
                        Icons.person_outline_rounded,
                        view.isOpen && view.guestCount != null
                            ? '${view.guestCount} ${t('sheet.people')}'
                            : t('sheet.guests'),
                      ),
                      const SizedBox(width: 12),
                      card(TableMenuAction.qr, Icons.qr_code_2_rounded, t('sheet.qr')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      card(
                        TableMenuAction.cancel,
                        Icons.cancel_outlined,
                        t('sheet.cancel'),
                        color: MeedColors.danger,
                      ),
                      const SizedBox(width: 12),
                      card(
                        TableMenuAction.transfer,
                        Icons.swap_horiz_rounded,
                        t('sheet.transfer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (view.isMerged)
                        card(TableMenuAction.unmerge, Icons.call_split_rounded, t('sheet.unmerge'))
                      else
                        const Spacer(),
                      const SizedBox(width: 12),
                      card(TableMenuAction.merge, Icons.call_merge_rounded, t('sheet.merge')),
                    ],
                  ),
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: _note == null
                          ? null
                          : Text(
                              _note!,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.2,
                                color: _noteIsError ? MeedColors.danger : MeedColors.inkSoft,
                              ),
                            ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _BigButton(
                          label: t(view.hasDishes ? 'sheet.orderMore' : 'sheet.order'),
                          enabled: orderEnabled,
                          onTap: () => _press(TableMenuAction.order, view, offline: offline),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BigButton(
                          label: t('sheet.bill'),
                          detail: '${currency == 'THB' ? '฿' : currency} ${t.money(view.total)}',
                          color: MeedColors.ringWaiting,
                          enabled: billEnabled,
                          onTap: () => _press(TableMenuAction.bill, view, offline: offline),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.t, required this.now});

  final TableSheetView view;
  final AppStrings t;
  final DateTime now;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.table_restaurant_outlined, size: 26, color: MeedColors.tableText),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    view.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: MeedColors.tableText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              view.openedAt == null ? t('sheet.notOpened') : t.since(view.openedAt!, now: now),
              style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
            ),
          ],
        ),
      );
}

/// The state of the table's food in words, with the dot in its ring colour, and a shortcut to
/// ordering while nothing has been ordered.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.view, required this.t, required this.onOrder});

  final TableSheetView view;
  final AppStrings t;
  final VoidCallback? onOrder;

  @override
  Widget build(BuildContext context) {
    final label = view.pendingPayment
        ? t('tables.pendingPayment')
        : view.foodStatus == TableFoodStatus.notOrdered
            ? t('sheet.notOrdered')
            : t(tableStatusKey(view.foodStatus));
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: MeedColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: view.foodStatus == TableFoodStatus.free
                  ? MeedColors.line
                  : tableRingColor(view.foodStatus),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
          if (onOrder != null)
            TextButton(
              onPressed: onOrder,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t('sheet.order')),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A button of the grid. One that cannot be used is faded rather than removed, so the grid never
/// moves under a thumb, and still answers a press with why.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = enabled ? color ?? MeedColors.tableText : MeedColors.inkSoft;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: MeedColors.line),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: MeedColors.card,
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: SizedBox(
              height: 76,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: ink),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.detail,
    this.color,
  });

  final String label;
  final String? detail;

  /// The branch's theme colour when null.
  final Color? color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          height: 72,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: color == null ? null : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, maxLines: 1, style: const TextStyle(height: 1.2)),
                if (detail != null)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, height: 1.2),
                  ),
              ],
            ),
          ),
        ),
      );
}
