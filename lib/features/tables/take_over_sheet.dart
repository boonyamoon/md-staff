import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dto/floor_dto.dart';
import 'active_table_controller.dart';

/// Offers the manager-PIN takeover for a table another handset is holding.
///
/// Returns true when the table is now this handset's. A waiter without takeover rights still sees
/// this sheet — the PIN is a manager's, not their own, and the server is what checks it.
Future<bool?> showTakeOverSheet(
  BuildContext context, {
  required FloorTable table,
  ApiFailure? failure,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TakeOverSheet(table: table, failure: failure),
    );

class _TakeOverSheet extends ConsumerStatefulWidget {
  const _TakeOverSheet({required this.table, this.failure});

  final FloorTable table;
  final ApiFailure? failure;

  @override
  ConsumerState<_TakeOverSheet> createState() => _TakeOverSheetState();
}

class _TakeOverSheetState extends ConsumerState<_TakeOverSheet> {
  final _pinController = TextEditingController();
  bool _showPinField = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  String get _holderName =>
      widget.table.claim?.holder.staffName ?? widget.failure?.holder?.staffName ?? '';

  String get _holderTerminal =>
      widget.table.claim?.holder.terminalName ?? widget.failure?.holder?.terminalName ?? '';

  Future<void> _takeOver() async {
    final t = ref.read(stringsProvider);
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = t('claim.pinRequired'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final claim = await ref
        .read(activeTableProvider.notifier)
        .takeOver(widget.table.floorItemId, pin);
    if (!mounted) return;
    if (claim != null) {
      Navigator.of(context).pop(true);
      return;
    }
    final failure = ref.read(activeTableProvider).failure;
    setState(() {
      _busy = false;
      _error = failure?.code == 'INVALID_MANAGER_PIN' ? t('claim.pinWrong') : failure?.message;
    });
    ref.read(activeTableProvider.notifier).acknowledgeFailure();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: MeedColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('claim.held.title'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${widget.table.label} · $_holderName'
            '${_holderTerminal.isEmpty ? '' : ' ($_holderTerminal)'}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            t('claim.held.body'),
            style: const TextStyle(fontSize: 14.5, color: MeedColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (!_showPinField)
            OutlinedButton.icon(
              onPressed: () => setState(() => _showPinField = true),
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text(t('claim.takeOver')),
            )
          else ...[
            TextField(
              controller: _pinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              onSubmitted: (_) => _takeOver(),
              decoration: InputDecoration(labelText: t('claim.managerPin')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: MeedColors.danger, fontSize: 14, height: 1.35),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _takeOver,
              child: Text(_busy ? t('common.loading') : t('claim.takeOver')),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(t('common.cancel')),
          ),
        ],
      ),
    );
  }
}
