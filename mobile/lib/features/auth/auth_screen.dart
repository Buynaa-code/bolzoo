import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../account/account_deletion.dart';
import '../../auth/auth_models.dart';
import '../../auth/auth_repository.dart';
import '../../auth/session_coordinator.dart';
import '../../data/account_scoped_store.dart';
import '../../data/app_controller.dart';
import '../../ui/theme.dart';
import '../../ui/components.dart';

/// Recovered legacy account gate. The shipped app uses the Cloudflare entrypoint.
class CloudAuthGate extends StatefulWidget {
  const CloudAuthGate({
    super.key,
    required this.documentsDirectory,
    required this.repository,
    required this.appBuilder,
    this.storeFactory,
    this.accountInitializer,
    this.onResumeAccountDeletion,
    this.navigatorObservers = const [],
  });
  final Directory documentsDirectory;
  final AuthRepository repository;
  final Widget Function(AppController) appBuilder;
  final AppStore Function(AccountScope)? storeFactory;
  final Future<void> Function(AccountScope)? accountInitializer;
  final Future<void> Function(AccountScope)? onResumeAccountDeletion;
  final List<NavigatorObserver> navigatorObservers;

  @override
  State<CloudAuthGate> createState() => _CloudAuthGateState();
}

class _CloudAuthGateState extends State<CloudAuthGate> {
  late final SessionCoordinator _sessions;
  late final StreamSubscription<AuthSession> _subscription;
  AuthSession _session = const AuthSession.signedOut();
  AccountScope? _scope;
  AppController? _controller;
  int _loadToken = 0;
  bool _loading = false;
  bool _failed = false;
  bool _signingOut = false;
  bool _deletionPending = false;
  bool _resumingDeletion = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessions = SessionCoordinator(widget.repository);
    _subscription = _sessions.sessions.listen(_applySession);
    _applySession(_sessions.current);
  }

  void _applySession(AuthSession session) {
    if (!mounted) return;
    final scope = session.isSignedIn ? session.scope : null;
    _session = session;
    if (scope == _scope) {
      setState(() {});
      return;
    }
    _scope = scope;
    _error = null;
    _signingOut = false;
    _resumingDeletion = false;
    unawaited(_loadAccount());
  }

  bool _accepts(AccountScope scope, int token) =>
      mounted && token == _loadToken && _sessions.accepts(scope);

  Future<void> _loadAccount() async {
    final scope = _scope;
    final token = ++_loadToken;
    final old = _controller;
    _controller = null;
    old?.dispose();
    setState(() {
      _loading = scope != null;
      _failed = false;
      _deletionPending = false;
    });
    if (scope == null) return;
    AppController? next;
    try {
      await widget.accountInitializer?.call(scope);
      if (!_accepts(scope, token)) return;
      next = AppController(
        widget.storeFactory?.call(scope) ??
            AccountScopedFileStore(
              documentsDirectory: widget.documentsDirectory,
              scope: scope,
            ),
      );
      await next.load();
      if (!_accepts(scope, token)) {
        next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _loading = false;
      });
    } on AccountDeletionPending {
      next?.dispose();
      if (_accepts(scope, token)) {
        setState(() {
          _loading = false;
          _deletionPending = true;
        });
      }
    } catch (_) {
      next?.dispose();
      if (_accepts(scope, token)) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _signOut() async {
    final scope = _scope;
    if (_signingOut || scope == null) return;
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await _sessions.signOut();
    } catch (error) {
      if (mounted && _sessions.accepts(scope)) {
        setState(
          () => _error = error is AuthFailure
              ? error.message
              : 'Гарч чадсангүй. Дахин оролдоно уу.',
        );
      }
    } finally {
      if (mounted && _sessions.accepts(scope)) {
        setState(() => _signingOut = false);
      }
    }
  }

  Future<void> _resumeDeletion() async {
    final scope = _scope;
    final resume = widget.onResumeAccountDeletion;
    if (_resumingDeletion || scope == null || resume == null) return;
    setState(() {
      _resumingDeletion = true;
      _error = null;
    });
    try {
      await resume(scope);
    } catch (_) {
      if (mounted && _sessions.accepts(scope)) {
        setState(
          () => _error =
              'Устгал дуусаагүй байна. Холболтоо шалгаад дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted && _sessions.accepts(scope)) {
        setState(() => _resumingDeletion = false);
      }
    }
  }

  @override
  void dispose() {
    _loadToken++;
    unawaited(_subscription.cancel());
    unawaited(_sessions.dispose());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    key: ValueKey(_scope),
    title: 'Нандин мөч',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('mn'),
    supportedLocales: const [Locale('mn'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    navigatorObservers: widget.navigatorObservers,
    home: !_session.isSignedIn
        ? AuthScreen(repository: widget.repository)
        : _controller != null
        ? widget.appBuilder(_controller!)
        : Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _deletionPending
                                  ? 'Бүртгэлийн устгалыг үргэлжлүүлье'
                                  : _failed
                                  ? 'Мэдээллийг нээж чадсангүй'
                                  : 'Мэдээллийг нээж байна…',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _deletionPending
                                  ? 'Та бүртгэлээ бүрмөсөн устгахаар баталгаажуулсан. Үүлэн хадгалалтын устгалыг дуусгахад интернэт хэрэгтэй.'
                                  : 'Хадгалсан мэдээллийг өөрчлөөгүй.',
                              textAlign: TextAlign.center,
                            ),
                            if (_error != null) Text(_error!),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed:
                                  _signingOut ||
                                      _resumingDeletion ||
                                      (_deletionPending &&
                                          widget.onResumeAccountDeletion ==
                                              null)
                                  ? null
                                  : _deletionPending
                                  ? _resumeDeletion
                                  : _loadAccount,
                              child: Text(
                                _resumingDeletion
                                    ? 'Устгаж байна…'
                                    : _deletionPending
                                    ? 'Устгал үргэлжлүүлэх'
                                    : 'Дахин оролдох',
                              ),
                            ),
                            TextButton(
                              onPressed: _signingOut || _resumingDeletion
                                  ? null
                                  : _signOut,
                              child: const Text('Бүртгэлээс гарах'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
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
