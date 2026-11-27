import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../bootstrap/session_controller.dart';
import '../menu/menu_catalog_controller.dart';

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
    final staffSession = session.session;
    final printing = config.value?.ordering.kitchenPrintingEnabled;

    return Scaffold(
      appBar: AppBar(title: Text(t('settings.title'))),
      // No SafeArea, as on the other scrolling screens: the list runs to the bottom edge and its
      // end is padded clear of the home indicator.
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 28 + MediaQuery.paddingOf(context).bottom),
        children: [
          _Section(
            title: t('settings.account'),
            rows: [
              _SettingsRow(
                icon: Icons.person_outline_rounded,
                title: t('settings.staff'),
                value: session.staffName ?? '-',
              ),
              _SettingsRow(
                icon: Icons.storefront_outlined,
                title: t('settings.branch'),
                value: config.value?.branch.branchName ?? '-',
                valueDetail: config.value?.branch.businessName,
              ),
              _SettingsRow(
                icon: Icons.phone_iphone_rounded,
                title: t('settings.terminal'),
                value: staffSession?.terminalName ?? '-',
                valueDetail: staffSession?.terminalCode,
              ),
              _SettingsRow(
                icon: Icons.print_outlined,
                title: t('settings.printing'),
                value: switch (printing) {
                  true => t('settings.printingOn'),
                  false => t('settings.printingOff'),
                  null => '-',
                },
                valueColor: printing == false ? MeedColors.danger : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(title: t('menu.title'), rows: const [_MenuDataRow()]),
          const SizedBox(height: 20),
          _Section(
            title: t('settings.language'),
            rows: [
              for (final option in AppLanguage.values)
                _SettingsRow(
                  // One icon for the group; the rows after it keep the same text column.
                  icon: option == AppLanguage.values.first ? Icons.translate_rounded : null,
                  title: option.label,
                  selected: option == language,
                  trailing: option == language
                      ? Icon(Icons.check_rounded, size: 22, color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () => ref.read(languageProvider.notifier).set(option),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // One action, not two: because the sign-in also paired the handset, signing out
          // undoes both — the session is revoked and the phone is free for the next person.
          _Section(
            rows: [
              _SettingsRow(
                icon: Icons.logout_rounded,
                title: t('settings.signOut'),
                subtitle: t('settings.signOutHint'),
                color: MeedColors.danger,
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    ref,
                    title: t('settings.signOut'),
                    body: t('settings.signOutConfirm'),
                    action: t('settings.signOut'),
                  );
                  if (confirmed) await ref.read(sessionProvider.notifier).signOut();
                },
              ),
            ],
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
    );
  }
}

/// How old the menu on this handset is, and the button that fetches it again.
class _MenuDataRow extends ConsumerWidget {
  const _MenuDataRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final menu = ref.watch(menuCatalogProvider);
    final fetchedAt = menu.fetchedAt;
    final failure = menu.failure;
    return _SettingsRow(
      icon: Icons.restaurant_menu_rounded,
      title: t('settings.menuData'),
      subtitle: failure != null
          ? t.failure(failure)
          : fetchedAt == null
              ? t('settings.neverUpdated')
              : '${t('settings.updatedAt')} ${t.time(fetchedAt, now: ref.watch(clockProvider)())}',
      trailing: menu.refreshing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : const Icon(Icons.refresh_rounded, size: 22, color: MeedColors.inkSoft),
      onTap: menu.refreshing ? null : () => ref.read(menuCatalogProvider.notifier).refresh(),
    );
  }
}

/// A titled card of rows.
class _Section extends StatelessWidget {
  const _Section({this.title, required this.rows});

  final String? title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(_SettingsRow.inset, 0, _SettingsRow.inset, 8),
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MeedColors.inkSoft,
                ),
              ),
            ),
          Card(
            // So that a row's ripple stops at the card's rounded corners.
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      );
}

/// Every row on this screen, so that icons, text and whatever sits at the end line up from one card
/// to the next: an icon slot, the title (with an optional line under it), then either a value or a
/// small widget against the right edge.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.valueDetail,
    this.valueColor,
    this.trailing,
    this.color,
    this.selected = false,
    this.onTap,
  });

  static const double inset = 16;
  static const double _iconSlot = 24;
  static const double _gap = 12;

  /// One line of the title or the value, which the icon and the trailing widget are centred on.
  static const double _lineHeight = 22;

  static const _smallStyle = TextStyle(fontSize: 13, height: 1.4, color: MeedColors.inkSoft);

  /// Null keeps the slot empty.
  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? value;
  final String? valueDetail;
  final Color? valueColor;
  final Widget? trailing;

  /// Tints the icon and the title.
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;

  Widget _slot(Widget? child, {double? width}) => SizedBox(
        width: width,
        height: _lineHeight,
        child: Center(widthFactor: width == null ? 1 : null, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: TextStyle(
        fontSize: 15,
        height: _lineHeight / 15,
        fontWeight: value == null ? FontWeight.w600 : FontWeight.w400,
        color: color ?? (value == null ? MeedColors.ink : MeedColors.inkSoft),
      ),
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleText,
        if (subtitle != null) Text(subtitle!, style: _smallStyle),
      ],
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: inset, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _slot(
                  icon == null ? null : Icon(icon, size: 20, color: color ?? MeedColors.inkSoft),
                  width: _iconSlot,
                ),
                const SizedBox(width: _gap),
                if (value == null)
                  Expanded(child: titleBlock)
                else ...[
                  // The title takes what it needs, up to a little over half; the value has the rest.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.55),
                    child: titleBlock,
                  ),
                  const SizedBox(width: _gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          value!,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 15,
                            height: _lineHeight / 15,
                            fontWeight: FontWeight.w600,
                            color: valueColor ?? MeedColors.ink,
                          ),
                        ),
                        if (valueDetail != null && valueDetail!.isNotEmpty)
                          Text(valueDetail!, textAlign: TextAlign.right, style: _smallStyle),
                      ],
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: _gap),
                  _slot(trailing),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
