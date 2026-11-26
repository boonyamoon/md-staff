import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/quantity_stepper.dart';
import '../../data/dto/floor_dto.dart';

/// Asks how many are at the table. Returns null when dismissed.
Future<int?> showGuestCountDialog(
  BuildContext context, {
  required String title,
  required int initial,
}) =>
    showDialog<int>(
      context: context,
      builder: (context) => _GuestCountDialog(title: title, initial: initial),
    );

class _GuestCountDialog extends ConsumerStatefulWidget {
  const _GuestCountDialog({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  ConsumerState<_GuestCountDialog> createState() => _GuestCountDialogState();
}

class _GuestCountDialogState extends ConsumerState<_GuestCountDialog> {
  late int _count = widget.initial.clamp(1, 99);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return AlertDialog(
      title: Text(widget.title),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          QuantityStepper(quantity: _count, onChanged: (value) => setState(() => _count = value)),
          const SizedBox(width: 12),
          Text(t('sheet.people')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('common.cancel')),
        ),
        // The theme's buttons fill their row, which an action row cannot give them.
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.of(context).pop(_count),
          child: Text(t('common.confirm')),
        ),
      ],
    );
  }
}

/// A yes/no before a change to a table. [destructive] paints the confirm button as a warning.
Future<bool> showTableConfirm(
  BuildContext context, {
  required AppStrings t,
  required String title,
  String? body,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t('common.cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: destructive ? MeedColors.danger : null,
            foregroundColor: destructive ? Colors.white : null,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t('common.confirm')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The code a guest scans to order for this table. Shown on screen: a handset prints nothing.
Future<void> showTableQr(BuildContext context, {required String label, required TableQr qr}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _QrDialog(label: label, qr: qr),
    );

class _QrDialog extends ConsumerWidget {
  const _QrDialog({required this.label, required this.qr});

  final String label;
  final TableQr qr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final expiresAt = qr.expiresAt;
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(t('qr.scan'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            // A fixed square: the code sizes itself from its constraints, which a dialog asking
            // for intrinsic sizes cannot supply. White whatever the theme, for scanners.
            SizedBox.square(
              dimension: 240,
              child: QrImageView(data: qr.url, backgroundColor: Colors.white),
            ),
            if (expiresAt != null) ...[
              const SizedBox(height: 8),
              Text(
                '${t('qr.validUntil')} ${t.time(expiresAt, now: ref.watch(clockProvider)())}',
                style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('common.close')),
            ),
          ],
        ),
      ),
    );
  }
}
