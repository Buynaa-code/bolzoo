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
import 'features/home/cloudflare_dashboard.dart';
import 'features/home/cloudflare_home_controller.dart';
import 'memories/memory_controller.dart';
import 'memories/memory_repository.dart';
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
    this.homeControllerFactory,
    this.paidFeaturesEnabled = cloudflarePaidFeaturesEnabled,
  });
  final CloudflareAuthRepository repository;
  final bool paidFeaturesEnabled;
  final SubscriptionController Function(CloudflareAuthRepository)?
  subscriptionControllerFactory;
  final TogetherReminderCoordinator Function(CloudflareAuthRepository)?
  reminderCoordinatorFactory;
  final CloudflareHomeController Function(CloudflareAuthRepository)?
  homeControllerFactory;

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
            homeControllerFactory: widget.homeControllerFactory,
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
    this.homeControllerFactory,
    required this.paidFeaturesEnabled,
  });
  final CloudflareAuthRepository repository;
  final bool paidFeaturesEnabled;
  final Future<void> Function() onSignOut;
  final SubscriptionController Function(CloudflareAuthRepository)?
  subscriptionControllerFactory;
  final TogetherReminderCoordinator Function(CloudflareAuthRepository)?
  reminderCoordinatorFactory;
  final CloudflareHomeController Function(CloudflareAuthRepository)?
  homeControllerFactory;

  @override
  State<_CloudflareHome> createState() => _CloudflareHomeState();
}

class _CloudflareHomeState extends State<_CloudflareHome>
    with WidgetsBindingObserver {
  late final SubscriptionController _billing;
  late final CloudflareCredential? _credential;
  late final TogetherReminderCoordinator _reminders;
  late final CloudflareHomeController _home;
  final _togetherKey = GlobalKey<TogetherScreenState>();
  bool _signingOut = false;
  bool _foreground = true, _changingTab = false;
  int _openRoutes = 0;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _credential = widget.repository.credential;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _home =
        widget.homeControllerFactory?.call(widget.repository) ??
        CloudflareHomeController(
          pairs: CloudflarePairRepository(widget.repository),
          together: CloudflareTogetherRepository(widget.repository),
          memories: widget.repository.transport is HttpCloudflareTransport
              ? MemoryController(CloudflareMemoryRepository(widget.repository))
              : null,
        );
    _home.setVisible(_foreground);
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
    _home.dispose();
    _reminders.dispose();
    _billing.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _reminders.setForeground(_foreground);
    _updateHomeVisibility();
    if (mounted) setState(() {});
  }

  void _updateHomeVisibility() =>
      _home.setVisible(_foreground && _openRoutes == 0 && _tab == 0);

  Future<void> _selectTab(int tab) async {
    if (!_current || _signingOut || _changingTab || tab == _tab) return;
    _changingTab = true;
    try {
      if (_togetherKey.currentState case final screen?) {
        if (!await screen.requestLeave()) return;
      }
      if (!mounted || !_current) return;
      setState(() => _tab = tab);
      _updateHomeVisibility();
    } finally {
      _changingTab = false;
    }
  }

  bool get _current =>
      _credential != null && widget.repository.accepts(_credential);

  void _open(Widget Function() screen) {
    if (!_current || _signingOut) return;
    final page = screen();
    setState(() => _openRoutes++);
    _updateHomeVisibility();
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page)).then((_) {
        if (mounted && _current) {
          setState(() => _openRoutes--);
          _updateHomeVisibility();
          unawaited(_reminders.refresh());
        }
      }),
    );
  }

  void _pairConnected() {
    if (!mounted || !_current || _signingOut) return;
    Navigator.of(context).pop();
    setState(() => _tab = 0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Та хоёр холбогдлоо. Хамтын мөчүүдээ эхлүүлээрэй.'),
      ),
    );
  }

  void _openPair() => _open(
    () => PairScreen(
      repository: CloudflarePairRepository(widget.repository),
      onPairChanged: (_) => _reminders.observe(null),
      onConnected: _pairConnected,
    ),
  );

  void _openTogether(
    TogetherSection section, {
    String? memoryId,
    String? eventId,
  }) => _open(
    () => TogetherScreen(
      auth: widget.repository,
      reminders: _reminders,
      initialSection: section,
      initialMemoryId: memoryId,
      initialEventId: eventId,
    ),
  );

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
  Widget build(BuildContext context) => PopScope(
    canPop: _tab == 0 || _tab == 1 || _tab == 2,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _tab > 2) unawaited(_selectTab(0));
    },
    child: Scaffold(
      appBar: _tab == 1 || _tab == 2
          ? null
          : AppBar(
              centerTitle: false,
              title: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Нандин ',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    TextSpan(
                      text: 'мөч',
                      style: TextStyle(
                        color: AppColors.pink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_tab != 4)
                  IconButton(
                    tooltip: 'Бидний мэдээлэл',
                    icon: const Icon(
                      Icons.favorite_border,
                      color: AppColors.pink,
                    ),
                    onPressed: () => _selectTab(4),
                  ),
                if (_tab == 4)
                  TextButton(
                    key: const Key('cloudflareSignOut'),
                    onPressed: _signingOut ? null : _signOut,
                    child: const Text('Гарах'),
                  ),
              ],
            ),
      body: SafeArea(
        top: _tab != 1 && _tab != 2,
        bottom: false,
        child: Visibility(
          visible: _foreground,
          maintainState: true,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _body(),
            ),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: NavigationBar(
          key: const Key('cloudflareBottomNavigation'),
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          height: 72,
          destinations: const [
            NavigationDestination(
              key: Key('navHome'),
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Нүүр',
            ),
            NavigationDestination(
              key: Key('navCalendar'),
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today),
              label: 'Хуанли',
            ),
            NavigationDestination(
              key: Key('navMemories'),
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library_rounded),
              label: 'Дурсамж',
            ),
            NavigationDestination(
              key: Key('navGifts'),
              icon: Icon(Icons.card_giftcard_outlined),
              selectedIcon: Icon(Icons.card_giftcard),
              label: 'Бэлэг',
            ),
            NavigationDestination(
              key: Key('navUs'),
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Бид',
            ),
          ],
        ),
      ),
    ),
  );

  Widget _body() {
    if (_tab == 1 || _tab == 2) {
      return TogetherScreen(
        key: _togetherKey,
        auth: widget.repository,
        reminders: _reminders,
        embedded: true,
        initialSection: _tab == 1
            ? TogetherSection.calendar
            : TogetherSection.memories,
        onHome: () => _selectTab(0),
        onPair: _openPair,
      );
    }
    if (_tab == 3) return _gifts();
    if (_tab == 4) return _profile();
    return CloudflareDashboard(
      controller: _home,
      onPair: _openPair,
      onCalendar: () => _openTogether(TogetherSection.calendar),
      onMemories: () => _selectTab(2),
      onFlorists: () => _open(() => const NearbyFloristsScreen()),
      onDaily: () => _openTogether(TogetherSection.daily),
      onWishes: () => _openTogether(TogetherSection.wishes),
      onEvent: (event) =>
          _openTogether(TogetherSection.calendar, eventId: event.id),
      onMemory: (memory) =>
          _openTogether(TogetherSection.memories, memoryId: memory.id),
      environmentNotice: _environmentNotice,
    );
  }

  Widget? get _environmentNotice {
    final origin = _nonProductionOrigin(widget.repository);
    return origin == null
        ? null
        : _BuildEnvironmentNotice(origin: origin, padding: EdgeInsets.zero);
  }

  Widget _gifts() => ListView(
    key: const Key('cloudflareGifts'),
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
    children: [
      const PageHeading(
        'Жижигхэн бэлэг,\nтомхон инээмсэглэл',
        subtitle: 'Хайртай хүндээ цаг, сэтгэлээ зориулъя.',
      ),
      SoftCard(
        color: AppColors.blush,
        child: Column(
          children: [
            const SizedBox(height: 16),
            const FlowerMark(size: 100),
            const SizedBox(height: 24),
            const Text(
              'Сэтгэлийн цэцэг',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ойрхон цэцгийн дэлгүүрээс\nтүүнд таалагдах баглааг олоорой.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('cloudflareOpenFlorists'),
              onPressed: () => _open(() => const NearbyFloristsScreen()),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Цэцгийн дэлгүүрүүд'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      HomeActionCard(
        icon: Icons.send_outlined,
        title: 'Болзоонд урья',
        subtitle: 'Кофе, кино эсвэл хамтдаа алхах цаг.',
        onTap: () => _openTogether(TogetherSection.calendar),
      ),
      const SizedBox(height: 12),
      HomeActionCard(
        icon: Icons.auto_awesome_outlined,
        title: 'Хүслийг нь мэдье',
        subtitle: 'Хамтын хүслийн жагсаалтаасаа санаа аваарай.',
        onTap: () => _openTogether(TogetherSection.wishes),
      ),
      if (widget.paidFeaturesEnabled) ..._paidDestinations(),
    ],
  );

  List<Widget> _paidDestinations() => [
    const SizedBox(height: 16),
    _HomeDestination(
      id: 'cloudflareOpenSubscription',
      icon: Icons.auto_awesome_outlined,
      title: 'Нандин мөч Plus',
      description: 'Багц болон эрхээ сэргээх.',
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
      description: 'Хоёуланд зориулсан карт бүтээгээрэй.',
      onTap: _openCards,
    ),
  ];

  Widget _profile() => ListView(
    key: const Key('cloudflareUs'),
    padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
    children: [
      const PageHeading(
        'Бидний булан',
        subtitle: 'Хамтын орон зай, өөрийн тохиргоо.',
      ),
      SoftCard(
        color: AppColors.blush,
        child: Column(
          children: [
            const HamtdaaMark(size: 64),
            const SizedBox(height: 12),
            Text(
              'Нэвтэрсэн имэйл: ${widget.repository.current.email ?? ''}',
              key: const Key('cloudflareSignedInEmail'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _HomeDestination(
        id: 'cloudflareOpenPair',
        icon: Icons.favorite_border,
        title: 'Бидний холболт',
        description: 'Хосоо урих, нэр болон холболтоо тохируулах.',
        onTap: _openPair,
      ),
      _HomeDestination(
        id: 'cloudflareOpenDaily',
        icon: Icons.chat_bubble_outline,
        title: 'Өдрийн асуулт',
        description: 'Бие биенээ илүү сайн танья.',
        onTap: () => _openTogether(TogetherSection.daily),
      ),
      _HomeDestination(
        id: 'cloudflareOpenWishes',
        icon: Icons.auto_awesome_outlined,
        title: 'Бидний хүслүүд',
        description: 'Хамтдаа биелүүлэх хүслүүдээ нэмье.',
        onTap: () => _openTogether(TogetherSection.wishes),
      ),
      _HomeDestination(
        id: 'cloudflareOpenAccount',
        icon: Icons.person_outline,
        title: 'Миний бүртгэл',
        description: 'Мэдээллээ татах, нууцлал, бүртгэлээ удирдах.',
        onTap: () =>
            _open(() => CloudflareAccountScreen(auth: widget.repository)),
      ),
      if (widget.paidFeaturesEnabled) ..._paidDestinations(),
      if (_nonProductionOrigin(widget.repository) case final origin?)
        _BuildEnvironmentNotice(origin: origin),
    ],
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
