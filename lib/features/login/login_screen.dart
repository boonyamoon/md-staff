import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../bootstrap/session_controller.dart';

/// Starting a shift on a paired handset: email and password, the same ones as the POS.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _emailController.text.contains('@') && _passwordController.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final session = await ref.read(shiftRepositoryProvider).login(
            email: _emailController.text,
            password: _passwordController.text,
          );
      await ref.read(sessionProvider.notifier).onShiftStarted(session);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final terminalName = session.credentials?.terminalName ?? '';
    final terminalCode = session.credentials?.terminalCode ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(t('login.title')),
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
            if (session.notice != null)
              NoticeBanner(message: t(session.notice!), tone: NoticeTone.warning),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                children: [
                  const Icon(Icons.badge_outlined, size: 52, color: MeedColors.brand),
                  const SizedBox(height: 14),
                  Text(
                    terminalName.isEmpty ? t('login.subtitle') : '$terminalName · $terminalCode',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: MeedColors.inkSoft),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailController,
                    onChanged: (_) => setState(() => _failure = null),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: t('setup.email')),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    onChanged: (_) => setState(() => _failure = null),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(labelText: t('setup.password')),
                  ),
                  if (_failure != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _failure!.code == 'INVALID_CREDENTIALS'
                          ? t('login.wrongCredentials')
                          : _failure!.message,
                      style: const TextStyle(color: MeedColors.danger, fontSize: 14, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: Text(t('login.signIn')),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      ),
    );
  }
}
