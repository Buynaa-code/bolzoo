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
import 'together/together_repository.dart';
import 'together/together_reminders.dart';
import 'notifications/reminders.dart';
import 'features/pair/pair_screen.dart';
import 'features/florists/nearby_florists_screen.dart';
import 'ui/components.dart';
import 'ui/theme.dart';

const cloudflareProductionApiUrl =
    'https://hamtdaa-api-production.mendmedey.workers.dev';
const cloudflareDefaultApiUrl = String.fromEnvironment(
  'CLOUDFLARE_API_URL',
  defaultValue: cloudflareProductionApiUrl,
);
// Store release candidates hide unfinished paid surfaces. Enabling the UI
// does not grant an entitlement or bypass the server's billing availability.
const cloudflarePaidFeaturesEnabled = bool.fromEnvironment(
  'NANDIN_ENABLE_PAID_FEATURES',
  defaultValue: false,
);

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
            apiUrl: cloudflareDefaultApiUrl,
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
    this.reminderCoordinatorFactory,
    this.paidFeaturesEnabled = cloudflarePaidFeaturesEnabled,
  });
  final CloudflareAuthRepository repository;
  final bool paidFeaturesEnabled;
  final SubscriptionController Function(CloudflareAuthRepository)?
  subscriptionControllerFactory;
  final TogetherReminderCoordinator Function(CloudflareAuthRepository)?
  reminderCoordinatorFactory;

  @override
  State<CloudflareOnboardingApp> createState() =>
      _CloudflareOnboardingAppState();
}

class _CloudflareOnboardingAppState extends State<CloudflareOnboardingApp> {
  late StreamSubscription<AuthSession> _subscription;
  late AuthSession _session;
  String? _signOutMessage;
  int _reminderGeneration = 0;

  Uri? get _customOrigin => _nonProductionOrigin(widget.repository);

  @override
  void initState() {
    super.initState();
    _session = widget.repository.current;
    if (!_session.isSignedIn) unawaited(_clearSignedOutReminders());
    _subscription = widget.repository.sessions.listen((session) {
      if (mounted) {
        ++_reminderGeneration;
        if (!session.isSignedIn) unawaited(_clearSignedOutReminders());
        setState(() {
          _session = session;
          if (session.isSignedIn) _signOutMessage = null;
        });
      }
    });
  }

  Future<void> _clearSignedOutReminders() async {
    final generation = _reminderGeneration;
    try {
      await Reminders.instance.initialize();
      if (!mounted ||
          generation != _reminderGeneration ||
          widget.repository.current.isSignedIn) {
        return;
      }
      await Reminders.instance.clear();
    } catch (_) {
      // No private notification content is scheduled. A later signed-in
      // coordinator retries initialization and reports any scheduling failure.
    }
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
            reminderCoordinatorFactory: widget.reminderCoordinatorFactory,
            paidFeaturesEnabled: widget.paidFeaturesEnabled,
          )
        : Scaffold(
            body: Column(
              children: [
                if (_customOrigin case final origin?)
                  Flexible(
                    child: SafeArea(
                      bottom: false,
                      child: SingleChildScrollView(
                        child: _BuildEnvironmentNotice(origin: origin),
                      ),
                    ),
                  ),
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
                Expanded(
                  flex: 2,
                  child: AuthScreen(repository: widget.repository),
                ),
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
    this.reminderCoordinatorFactory,
    required this.paidFeaturesEnabled,
  });
  final CloudflareAuthRepository repository;
  final bool paidFeaturesEnabled;
  final Future<void> Function() onSignOut;
  final SubscriptionController Function(CloudflareAuthRepository)?
  subscriptionControllerFactory;
  final TogetherReminderCoordinator Function(CloudflareAuthRepository)?
  reminderCoordinatorFactory;

  @override
  State<_CloudflareHome> createState() => _CloudflareHomeState();
}

class _CloudflareHomeState extends State<_CloudflareHome>
    with WidgetsBindingObserver {
  late final SubscriptionController _billing;
  late final CloudflareCredential? _credential;
  late final TogetherReminderCoordinator _reminders;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _credential = widget.repository.credential;
    WidgetsBinding.instance.addObserver(this);
    _reminders =
        widget.reminderCoordinatorFactory?.call(widget.repository) ??
        TogetherReminderCoordinator(
          repository: CloudflareTogetherRepository(widget.repository),
          preferences: SecureTogetherReminderPreferences(
            namespace: widget.repository.transport is HttpCloudflareTransport
                ? (widget.repository.transport as HttpCloudflareTransport)
                      .baseUri
                      .origin
                : 'custom',
          ),
        );
    _reminders.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    unawaited(_reminders.initialize());
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
    WidgetsBinding.instance.removeObserver(this);
    _reminders.dispose();
    _billing.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _reminders.setForeground(state == AppLifecycleState.resumed);
  }

  bool get _current =>
      _credential != null && widget.repository.accepts(_credential);

  void _open(Widget Function() screen) {
    if (!_current || _signingOut) return;
    final page = screen();
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page)).then((_) {
        if (mounted && _current) unawaited(_reminders.refresh());
      }),
    );
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

  void _openCards() {
    if (!widget.paidFeaturesEnabled) return;
    _open(() => PremiumCardsScreen(auth: widget.repository));
  }

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
              if (_nonProductionOrigin(widget.repository)
                  case final origin?) ...[
                _BuildEnvironmentNotice(
                  origin: origin,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 20),
              ],
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
              const SizedBox(height: 12),
              Text(
                'Нэвтэрсэн имэйл: ${widget.repository.current.email ?? ''}',
                key: const Key('cloudflareSignedInEmail'),
                style: const TextStyle(color: AppColors.muted, height: 1.5),
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
                    onPairChanged: (_) => _reminders.observe(null),
                  ),
                ),
              ),
              _HomeDestination(
                id: 'cloudflareOpenTogether',
                icon: Icons.calendar_month_outlined,
                title: 'Бид хоёр',
                description: 'Хамтын хуанли, хүслүүд, болзоо, өдрийн асуулт.',
                onTap: () => _open(
                  () => TogetherScreen(
                    auth: widget.repository,
                    reminders: _reminders,
                  ),
                ),
              ),
              _HomeDestination(
                id: 'cloudflareOpenFlorists',
                icon: Icons.local_florist_outlined,
                title: 'Ойрхон цэцгийн дэлгүүр',
                description: 'Цэцгэн газрын зураг дээрээс бэлгээ олоорой.',
                onTap: () => _open(() => const NearbyFloristsScreen()),
              ),
              if (widget.paidFeaturesEnabled)
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
              if (widget.paidFeaturesEnabled)
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

Uri? _nonProductionOrigin(CloudflareAuthRepository repository) {
  final transport = repository.transport;
  if (transport is! HttpCloudflareTransport) return null;
  final origin = transport.baseUri.origin;
  return origin == Uri.parse(cloudflareProductionApiUrl).origin
      ? null
      : Uri.parse(origin);
}

class _BuildEnvironmentNotice extends StatelessWidget {
  const _BuildEnvironmentNotice({
    required this.origin,
    this.padding = const EdgeInsets.all(16),
  });
  final Uri origin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final staging =
        origin.origin == 'https://hamtdaa-api-staging.mendmedey.workers.dev';
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Container(
        key: const Key('cloudflareBuildEnvironmentNotice'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.tertiary),
        ),
        child: DefaultTextStyle(
          style: TextStyle(color: colors.onTertiaryContainer, height: 1.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                staging ? 'Туршилтын хувилбар' : 'Өөр сервертэй хувилбар',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Урилгын код зөвхөн ижил серверт ажиллана. Хоёр утсандаа ижил хувилбарын апп ашиглаарай.',
              ),
              const SizedBox(height: 6),
              Text(
                'Сервер: ${origin.origin}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
