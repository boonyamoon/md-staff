import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../bootstrap/session_controller.dart';

/// Where it is, who is on it, which language, and the two destructive actions: end the shift, and
/// unpair the handset.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<bool> _confirm(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String action,
  }) async {
    final t = ref.read(stringsProvider);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final config = ref.watch(configProvider);
    final version = ref.watch(appVersionProvider);
    final language = ref.watch(languageProvider);
    final credentials = session.credentials;

    return Scaffold(
      appBar: AppBar(title: Text(t('settings.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Card(
              child: Column(
                children: [
                  _Row(
                    icon: Icons.person_outline_rounded,
                    label: t('settings.staff'),
                    value: session.staffName ?? '-',
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: Icons.storefront_outlined,
                    label: t('settings.branch'),
                    value: config.value?.branch.branchName ?? '-',
                    subtitle: config.value?.branch.businessName,
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: Icons.phone_iphone_rounded,
                    label: t('settings.terminal'),
                    value: credentials?.terminalName ?? '-',
                    subtitle: credentials?.terminalCode,
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: Icons.print_outlined,
                    label: t('settings.printing'),
                    value: switch (config.value?.ordering.kitchenPrintingEnabled) {
                      true => t('settings.printingOn'),
                      false => t('settings.printingOff'),
                      null => '-',
                    },
                    valueColor: config.value?.ordering.kitchenPrintingEnabled == false
                        ? MeedColors.danger
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: RadioGroup<AppLanguage>(
                groupValue: language,
                onChanged: (value) {
                  if (value != null) ref.read(languageProvider.notifier).set(value);
                },
                child: Column(
                  children: [
                    for (final option in AppLanguage.values) ...[
                      if (option != AppLanguage.values.first) const Divider(height: 1),
                      RadioListTile<AppLanguage>(value: option, title: Text(option.label)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: Text(t('shift.signOut')),
                    onTap: () async {
                      final confirmed = await _confirm(
                        context,
                        ref,
                        title: t('shift.signOut'),
                        body: t('shift.signOutConfirm'),
                        action: t('shift.signOut'),
                      );
                      if (confirmed) await ref.read(sessionProvider.notifier).signOut();
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.link_off_rounded, color: MeedColors.danger),
                    title: Text(
                      t('settings.unpair'),
                      style: const TextStyle(color: MeedColors.danger),
                    ),
                    onTap: () async {
                      final confirmed = await _confirm(
                        context,
                        ref,
                        title: t('settings.unpair'),
                        body: t('settings.unpairConfirm'),
                        action: t('settings.unpair'),
                      );
                      if (confirmed) await ref.read(sessionProvider.notifier).unpair();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Text(
                    '${t('settings.version')} ${version.value ?? '-'}',
                    style: const TextStyle(fontSize: 13, color: MeedColors.inkSoft),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConfig.apiBaseUrl,
                    style: const TextStyle(fontSize: 12, color: MeedColors.inkSoft),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: MeedColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: MeedColors.inkSoft),
              ),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 13, color: MeedColors.inkSoft),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
