import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth/auth_models.dart';
import 'billing/billing_repository.dart';
import 'billing/store_gateway.dart';
import 'billing/subscription_controller.dart';
import 'cloudflare/cloudflare_auth_repository.dart';
import 'cloudflare/cloudflare_environment.dart';
import 'cloudflare/cloudflare_pair_repository.dart';
import 'cloudflare/cloudflare_session_storage.dart';
import 'cloudflare/cloudflare_transport.dart';
import 'features/auth/auth_screen.dart';
import 'features/account/cloudflare_account_screen.dart';
import 'features/premium_cards/premium_cards_screen.dart';
import 'features/subscription/subscription_screen.dart';
import 'together/together_screen.dart';
import 'features/pair/pair_screen.dart';
import 'ui/components.dart';
import 'ui/theme.dart';

/// Default Cloudflare entrypoint. Private routes belong to one login session.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  runApp(const CloudflareBootstrap());
}

class CloudflareBootstrap extends StatefulWidget {
  const CloudflareBootstrap({super.key, this.environment});
  final CloudflareEnvironment? environment;

  @override
  State<CloudflareBootstrap> createState() => _CloudflareBootstrapState();
}

class _CloudflareBootstrapState extends State<CloudflareBootstrap> {
  CloudflareAuthRepository? _auth;
  CloudflareTransport? _transport;
  bool _ready = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final environment =
          widget.environment ??
          CloudflareEnvironment(
            apiUrl: const String.fromEnvironment(
              'CLOUDFLARE_API_URL',
              defaultValue:
                  'https://hamtdaa-api-production.mendmedey.workers.dev',
            ),
            allowLoopback:
                !kReleaseMode &&
                const bool.fromEnvironment('CLOUDFLARE_ALLOW_LOOPBACK'),
          );
      if (environment.validationError != null) {
        setState(() => _error = environment.validationError);
        return;
      }
      _transport ??= HttpCloudflareTransport(environment.baseUri);
      _auth ??= CloudflareAuthRepository(
        transport: _transport!,
        storage: SecureCloudflareSessionStorage(environment.baseUri),
      );
      await _auth!.initialize();
      if (mounted) setState(() => _ready = true);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Нэвтрэлтийг шалгаж чадсангүй. Дахин оролдоорой.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    unawaited(_auth?.dispose());
    _transport?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return CloudflareOnboardingApp(repository: _auth!);
    return MaterialApp(
      title: 'Нандин мөч',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const HamtdaaMark(size: 64),
                        const SizedBox(height: 24),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _initialize,
                          child: const Text('Дахин оролдох'),
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

class CloudflareOnboardingApp extends StatefulWidget {
  const CloudflareOnboardingApp({
    super.key,
    required this.repository,
    this.subscriptionControllerFactory,
  });
  final CloudflareAuthRepository repository;
  final SubscriptionController Function(CloudflareAuthRepository)?
  subscriptionControllerFactory;

  @override
  State<CloudflareOnboardingApp> createState() =>
      _CloudflareOnboardingAppState();
}

class _CloudflareOnboardingAppState extends State<CloudflareOnboardingApp> {
  late StreamSubscription<AuthSession> _subscription;
  late AuthSession _session;
  String? _signOutMessage;

  @override
  void initState() {
    super.initState();
    _session = widget.repository.current;
    _subscription = widget.repository.sessions.listen((session) {
      if (mounted) {
        setState(() {
          _session = session;
          if (session.isSignedIn) _signOutMessage = null;
        });
      }
    });
  }

  Future<void> _signOut() async {
    try {
      await widget.repository.signOut();
    } catch (error) {
      if (!mounted || widget.repository.current.isSignedIn) return;
      setState(
        () => _signOutMessage = error is AuthFailure
            ? error.message
            : 'Гаралтыг бүрэн баталгаажуулж чадсангүй. Дахин нэвтэрч шалгаарай.',
      );
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    // Destroy every private route and dialog when the login identity changes.
    key: ValueKey(_session.isSignedIn ? _session.scope : null),
    title: 'Нандин мөч',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('mn'),
    supportedLocales: const [Locale('mn'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    navigatorObservers: [pairRouteObserver],
    home: _session.isSignedIn
        ? _CloudflareHome(
            repository: widget.repository,
            onSignOut: _signOut,
            subscriptionControllerFactory: widget.subscriptionControllerFactory,
          )
        : Scaffold(
            body: Column(
              children: [
                if (_signOutMessage != null)
                  SafeArea(
                    bottom: false,
                    child: MaterialBanner(
                      content: Text(_signOutMessage!),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _signOutMessage = null),
                          child: const Text('Хаах'),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: AuthScreen(repository: widget.repository)),
              ],
            ),
          ),
  );
}

class _CloudflareHome extends StatefulWidget {
  const _CloudflareHome({
    required this.repository,
    required this.onSignOut,
    this.subscriptionControllerFactory,
  });
  final CloudflareAuthRepository repository;
  final Future<void> Function() onSignOut;
  final SubscriptionController Function(CloudflareAuthRepository)?
  subscriptionControllerFactory;

  @override
  State<_CloudflareHome> createState() => _CloudflareHomeState();
}

class _CloudflareHomeState extends State<_CloudflareHome> {
  late final SubscriptionController _billing;
  late final CloudflareCredential? _credential;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _credential = widget.repository.credential;
    _billing =
        widget.subscriptionControllerFactory?.call(widget.repository) ??
        SubscriptionController(
          repository: CloudflareBillingRepository(widget.repository),
          store: InAppPurchaseGateway(),
        );
    // Listen for unfinished native purchases throughout this account's session.
    unawaited(_billing.initialize());
  }

  @override
  void dispose() {
    _billing.dispose();
    super.dispose();
  }

  bool get _current =>
      _credential != null && widget.repository.accepts(_credential);

  void _open(Widget Function() screen) {
    if (!_current || _signingOut) return;
    final page = screen();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  SubscriptionLegalLinks get _legalLinks {
    final transport = widget.repository.transport;
    final base = transport is HttpCloudflareTransport
        ? transport.baseUri
        : Uri();
    return SubscriptionLegalLinks(
      terms: base.resolve('/terms'),
      privacy: base.resolve('/privacy'),
    );
  }

  void _openCards() => _open(() => PremiumCardsScreen(auth: widget.repository));

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await widget.onSignOut();
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Нандин мөч'),
      actions: [
        TextButton(
          key: const Key('cloudflareSignOut'),
          onPressed: _signingOut ? null : _signOut,
          child: const Text('Гарах'),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            key: const Key('cloudflareHome'),
            padding: const EdgeInsets.all(24),
            children: [
              const Center(child: HamtdaaMark(size: 72)),
              const SizedBox(height: 24),
              const Text(
                'Хоёулаа хамтдаа эхэлье',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              const Text(
                'Хамтын төлөвлөгөө, өдөр тутмын яриа, дурсах нандин мөчүүд.',
                style: TextStyle(color: AppColors.muted, height: 1.6),
              ),
              const SizedBox(height: 24),
              _HomeDestination(
                id: 'cloudflareOpenPair',
                icon: Icons.favorite_border,
                title: 'Хосоор холбогдох',
                description:
                    'Нэрээ тохируулж, хоёр талын зөвшөөрлөөр холбогдоорой.',
                onTap: () => _open(
                  () => PairScreen(
                    repository: CloudflarePairRepository(widget.repository),
                  ),
                ),
              ),
              _HomeDestination(
                id: 'cloudflareOpenTogether',
                icon: Icons.calendar_month_outlined,
                title: 'Бид хоёр',
                description: 'Хамтын хуанли, хүслүүд, болзоо, өдрийн асуулт.',
                onTap: () =>
                    _open(() => TogetherScreen(auth: widget.repository)),
              ),
              _HomeDestination(
                id: 'cloudflareOpenSubscription',
                icon: Icons.auto_awesome_outlined,
                title: 'Нандин мөч Plus',
                description: 'Багц, худалдан авалт болон эрхээ сэргээх.',
                onTap: () => _open(
                  () => SubscriptionScreen(
                    controller: _billing,
                    legalLinks: _legalLinks,
                    onOpenCards: _openCards,
                  ),
                ),
              ),
              _HomeDestination(
                id: 'cloudflareOpenPremiumCards',
                icon: Icons.style_outlined,
                title: 'Хосын карт',
                description:
                    'Plus эрхээрээ хоёуланд зориулсан карт бүтээгээрэй.',
                onTap: _openCards,
              ),
              _HomeDestination(
                id: 'cloudflareOpenAccount',
                icon: Icons.person_outline,
                title: 'Миний бүртгэл',
                description:
                    'Мэдээллээ татах, нууцлал болон бүртгэлийн тохиргоо.',
                onTap: () => _open(
                  () => CloudflareAccountScreen(auth: widget.repository),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HomeDestination extends StatelessWidget {
  const _HomeDestination({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final String id, title, description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SoftCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        key: Key(id),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(icon, color: AppColors.pink),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
  );
}
