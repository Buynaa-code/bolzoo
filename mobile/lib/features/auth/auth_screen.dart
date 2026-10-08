import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../auth/auth_models.dart';
import '../../auth/auth_repository.dart';
import '../../data/account_scoped_store.dart';
import '../../data/app_controller.dart';
import '../../main_supabase_legacy.dart' show AppShell;
import '../../ui/theme.dart';
import '../../ui/components.dart';

class CloudAuthGate extends StatefulWidget {
  const CloudAuthGate({
    super.key,
    required this.documentsDirectory,
    required this.repository,
  });

  final Directory documentsDirectory;
  final AuthRepository repository;

  @override
  State<CloudAuthGate> createState() => _CloudAuthGateState();
}

class _CloudAuthGateState extends State<CloudAuthGate> {
  late final StreamSubscription<AuthSession> _subscription;
  AuthSession _session = const AuthSession.signedOut();
  AppController? _controller;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.repository.sessions.listen(_applySession);
    _applySession(widget.repository.current);
  }

  Future<void> _applySession(AuthSession session) async {
    if (!mounted) return;
    final token = ++_loadToken;
    final old = _controller;
    _controller = null;
    old?.dispose();
    setState(() => _session = session);
    if (!session.isSignedIn) return;
    final next = AppController(
      AccountScopedFileStore(
        documentsDirectory: widget.documentsDirectory,
        scope: session.scope,
      ),
    );
    try {
      await next.load();
      if (!mounted ||
          token != _loadToken ||
          !widget.repository.current.isSignedIn) {
        next.dispose();
        return;
      }
      setState(() => _controller = next);
    } catch (_) {
      next.dispose();
      if (mounted && token == _loadToken) {
        setState(
          () => _session = session.withMessage('Мэдээллийг нээж чадсангүй.'),
        );
      }
    }
  }

  @override
  void dispose() {
    _loadToken++;
    _subscription.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Хамтдаа',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('mn'),
    supportedLocales: const [Locale('mn'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: _controller != null && _session.isSignedIn
        ? AppShell(controller: _controller!)
        : AuthScreen(repository: widget.repository, onSignedIn: _applySession),
  );
}

/// Two-step email OTP screen shared by onboarding and re-authentication.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.repository, this.onSignedIn});

  final AuthRepository repository;
  final ValueChanged<AuthSession>? onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  Timer? _cooldownTimer;
  final _cooldowns = <String, int>{};
  AccountScope? _notifiedScope;
  String? _challengeEmail;
  int _challengeVersion = 0;
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.addListener(_emailChanged);
  }

  String get _normalizedEmail => _email.text.trim().toLowerCase();
  int get _cooldown => _cooldowns[_normalizedEmail] ?? 0;
  bool _current(int version) => mounted && version == _challengeVersion;

  void _notifySignedIn(AuthSession session) {
    if (!mounted ||
        !session.isSignedIn ||
        _notifiedScope == session.scope ||
        (_challengeEmail != null &&
            session.email?.trim().toLowerCase() != _challengeEmail)) {
      return;
    }
    _notifiedScope = session.scope;
    widget.onSignedIn?.call(session);
  }

  void _emailChanged() {
    if (_challengeEmail != null && _normalizedEmail != _challengeEmail) {
      _changeEmail();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _changeEmail() {
    // A late request for the previous address cannot restore its challenge.
    // Preserve per-address cooldowns even if the user changes away and back.
    _challengeVersion++;
    _code.clear();
    setState(() {
      _challengeEmail = null;
      _codeSent = false;
      _busy = false;
      _error = null;
    });
  }

  void _startCooldown(String email) {
    _cooldowns[email] = 60;
    _cooldownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _cooldowns.updateAll((_, remaining) => remaining - 1);
        _cooldowns.removeWhere((_, remaining) => remaining <= 0);
        if (_cooldowns.isEmpty) {
          _cooldownTimer?.cancel();
          _cooldownTimer = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _challengeVersion++;
    _cooldownTimer?.cancel();
    _email.removeListener(_emailChanged);
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy || _cooldown > 0) return;
    final email = _normalizedEmail;
    final version = ++_challengeVersion;
    _challengeEmail = email;
    _code.clear();
    await _run(version, () async {
      await widget.repository.requestEmailCode(email);
      if (!_current(version)) return;
      setState(() {
        _codeSent = true;
        _startCooldown(email);
      });
    });
  }

  Future<void> _verify() async {
    final email = _challengeEmail;
    if (!_codeSent || email == null || email != _normalizedEmail) return;
    final version = _challengeVersion;
    await _run(version, () async {
      final session = await widget.repository.verifyEmailCode(
        email,
        _code.text,
      );
      // The app shell observes repository events. Deliver this screen's optional
      // callback only from its still-current verification, never both paths.
      if (_current(version)) _notifySignedIn(session);
    });
  }

  Future<void> _run(int version, Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } on AuthFailure catch (error) {
      if (_current(version)) setState(() => _error = error.message);
    } catch (_) {
      if (_current(version)) {
        setState(() => _error = 'Түр алдаа гарлаа. Дахин оролдоно уу.');
      }
    } finally {
      if (_current(version)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: HamtdaaMark(size: 112),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Нандин мөч',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Хосын дурсамжаа хоёр утаснаас хамт хадгалаарай.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Имэйл хаяг',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_codeSent) ...[
                    TextField(
                      controller: _code,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '6 оронтой код',
                        hintText: '123456',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: colors.error)),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    onPressed: _busy || (!_codeSent && _cooldown > 0)
                        ? null
                        : (_codeSent ? _verify : _sendCode),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _codeSent
                                ? 'Нэвтрэх'
                                : _cooldown > 0
                                ? 'Код авах · $_cooldown сек'
                                : 'Код авах',
                          ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy || _cooldown > 0 ? null : _sendCode,
                      child: Text(
                        _cooldown > 0
                            ? 'Дахин илгээх · $_cooldown сек'
                            : 'Код дахин илгээх',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _changeEmail,
                      child: const Text('Имэйлээ өөрчлөх'),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    'Таны мэдээлэл зөвшөөрөлгүй хүнд харагдахгүй. Хосоо холбосны дараа зөвшөөрсөн мэдээлэл л хуваалцана.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
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
