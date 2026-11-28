import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/setup_dto.dart';
import '../bootstrap/session_controller.dart';
import 'setup_controller.dart';

/// The handset's one sign-in: a waiter's own email, then the branch and the terminal. Done once
/// per phone — the app keeps itself signed in from then on.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deviceNameController = TextEditingController();
  bool _deviceNameTouched = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);
    final notice = ref.watch(sessionProvider).notice;

    // Keep the prefilled device name in the field until a manager edits it themselves.
    if (!_deviceNameTouched && _deviceNameController.text != state.deviceName) {
      _deviceNameController.text = state.deviceName;
    }

    ref.listen(setupControllerProvider, (previous, next) {
      final session = next.signedIn;
      if (session != null && previous?.signedIn == null) {
        ref.read(sessionProvider.notifier).onSignedIn(session);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(t('setup.title')),
        leading: state.step == SetupStep.login
            ? null
            : BackButton(onPressed: controller.back),
        actions: [
          IconButton(
            tooltip: t('settings.language'),
            icon: const Icon(Icons.translate_rounded),
            onPressed: ref.read(languageProvider.notifier).toggle,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (notice != null)
              NoticeBanner(message: t(notice), tone: NoticeTone.danger),
            Expanded(
              child: AbsorbPointer(
                absorbing: state.loading,
                child: switch (state.step) {
                  SetupStep.login => _LoginStep(
                      state: state,
                      t: t,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      onEmailChanged: controller.emailChanged,
                      onPasswordChanged: controller.passwordChanged,
                      onSubmit: controller.login,
                    ),
                  SetupStep.branch => _BranchStep(
                      state: state,
                      t: t,
                      onSelect: controller.selectBranch,
                      onConfirm: controller.confirmBranch,
                    ),
                  SetupStep.terminal => _TerminalStep(
                      state: state,
                      t: t,
                      deviceNameController: _deviceNameController,
                      onSelectTerminal: controller.selectTerminal,
                      onDeviceNameChanged: (value) {
                        _deviceNameTouched = true;
                        controller.deviceNameChanged(value);
                      },
                      onFinish: controller.finish,
                    ),
                  SetupStep.noBusiness => _DeadEnd(
                      message: t('setup.noBusiness'),
                      actionLabel: t('common.back'),
                      onAction: controller.signOut,
                    ),
                  SetupStep.noPermission => _DeadEnd(
                      message: t('setup.noPermission'),
                      actionLabel: t('common.back'),
                      onAction: controller.signOut,
                    ),
                },
              ),
            ),
            if (state.loading) const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      ),
    );
  }
}

class _LoginStep extends StatelessWidget {
  const _LoginStep({
    required this.state,
    required this.t,
    required this.emailController,
    required this.passwordController,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onSubmit,
  });

  final SetupState state;
  final AppStrings t;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Icon(Icons.phone_iphone_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            t('setup.intro'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: MeedColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: emailController,
            onChanged: onEmailChanged,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: t('setup.email')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: passwordController,
            onChanged: onPasswordChanged,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(labelText: t('setup.password')),
          ),
          if (state.missingCredentials) ...[
            const SizedBox(height: 10),
            Text(
              t('setup.missingCredentials'),
              style: const TextStyle(color: MeedColors.danger, fontSize: 14),
            ),
          ],
          if (state.failure != null) ...[
            const SizedBox(height: 10),
            _FailureText(message: t.failure(state.failure!)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.canLogin ? onSubmit : null,
            child: Text(t('setup.signIn')),
          ),
        ],
      );
}

class _BranchStep extends StatelessWidget {
  const _BranchStep({
    required this.state,
    required this.t,
    required this.onSelect,
    required this.onConfirm,
  });

  final SetupState state;
  final AppStrings t;
  final ValueChanged<BranchOption> onSelect;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              itemCount: state.branches.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      t('setup.chooseBranch'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  );
                }
                final branch = state.branches[index - 1];
                final selected = state.selectedBranch?.id == branch.id;
                return _ChoiceCard(
                  title: branch.name,
                  subtitle: branch.businessName,
                  selected: selected,
                  onTap: () => onSelect(branch),
                );
              },
            ),
          ),
          if (state.failure != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _FailureText(message: t.failure(state.failure!)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: FilledButton(
              onPressed: state.selectedBranch == null || state.loading ? null : onConfirm,
              child: Text(t('common.confirm')),
            ),
          ),
        ],
      );
}

class _TerminalStep extends StatelessWidget {
  const _TerminalStep({
    required this.state,
    required this.t,
    required this.deviceNameController,
    required this.onSelectTerminal,
    required this.onDeviceNameChanged,
    required this.onFinish,
  });

  final SetupState state;
  final AppStrings t;
  final TextEditingController deviceNameController;
  final ValueChanged<String?> onSelectTerminal;
  final ValueChanged<String> onDeviceNameChanged;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final free = state.terminals.where((term) => !term.isPaired).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            children: [
              Text(
                t('setup.chooseTerminal'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (state.terminals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    t('setup.noTerminal'),
                    style: const TextStyle(color: MeedColors.inkSoft, height: 1.4),
                  ),
                )
              else ...[
                _ChoiceCard(
                  title: t('setup.autoTerminal'),
                  // With none free, signing in still works: the server takes over the idlest one.
                  subtitle: free.isEmpty ? t('setup.allTaken') : null,
                  selected: state.selectedTerminalId == null,
                  onTap: () => onSelectTerminal(null),
                ),
                const SizedBox(height: 10),
                for (final terminal in state.terminals) ...[
                  _ChoiceCard(
                    title: '${terminal.terminalName} (${terminal.terminalCode})',
                    subtitle: terminal.isPaired
                        ? '${t('setup.terminalTaken')}${terminal.deviceName == null ? '' : ' • ${terminal.deviceName}'}'
                        : t('setup.terminalFree'),
                    selected: state.selectedTerminalId == terminal.terminalId,
                    enabled: !terminal.isPaired,
                    onTap: () => onSelectTerminal(terminal.terminalId),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 8),
              TextField(
                controller: deviceNameController,
                onChanged: onDeviceNameChanged,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: t('setup.deviceName')),
              ),
            ],
          ),
        ),
        if (state.failure != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _FailureText(message: t.failure(state.failure!)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: FilledButton(
            onPressed: state.canFinish ? onFinish : null,
            child: Text(t('setup.finish')),
          ),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: selected ? Theme.of(context).colorScheme.primaryTint : MeedColors.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? Theme.of(context).colorScheme.primary : MeedColors.line,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DeadEnd extends StatelessWidget {
  const _DeadEnd({required this.message, required this.actionLabel, required this.onAction});

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block_rounded, size: 48, color: MeedColors.inkSoft),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      );
}

class _FailureText extends StatelessWidget {
  const _FailureText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
        message,
        style: const TextStyle(color: MeedColors.danger, fontSize: 14, height: 1.35),
      );
}
