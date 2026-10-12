import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/app_environment.dart';
import 'auth/auth_models.dart';
import 'auth/supabase_auth_repository.dart';
import 'auth/secure_auth_storage.dart';
import 'features/auth/auth_screen.dart';
import 'features/pair/pair_screen.dart';
import 'pair/pair_repository.dart';
import 'pair/supabase_pair_repository.dart';
import 'content/content_repository.dart';
import 'content/supabase_content_repository.dart';
import 'account/account_deletion.dart';
import 'account/account_initializer.dart';
import 'account/account_repository.dart';
import 'account/account_export.dart';
import 'notifications/reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'data/app_controller.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/memories/memories_screen.dart';
import 'features/home/home_screen.dart';
import 'features/gifts/gifts_screen.dart';
import 'features/profile/profile_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  runApp(const AppBootstrap());
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.environment});
  final AppEnvironment? environment;
  @override
  State<AppBootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<AppBootstrap> {
  AppController? _controller;
  bool _failed = false;
  bool _loading = false;
  String? _configurationError;
  SupabaseAuthRepository? _authRepository;
  Directory? _documentsDirectory;
  AccountDeletionCoordinator? _deletions;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
      _configurationError = null;
    });
    AppController? next;
    SupabaseAuthRepository? nextAuth;
    try {
      final environment =
          widget.environment ?? AppEnvironment.fromDartDefines();
      final error = environment.validationError;
      if (error != null) {
        setState(() {
          _configurationError = error;
          _failed = true;
        });
        return;
      }
      // A signed-out cold launch must also remove the prior login's notices.
      // Notification availability must not prevent local data or auth startup.
      try {
        await Reminders.instance.initialize();
        if (!mounted) return;
        await Reminders.instance.clear();
      } catch (_) {
        // The shell retries silent initialization when it becomes available.
      }
      if (!mounted) return;
      final directory = await getApplicationDocumentsDirectory();
      _documentsDirectory = directory;
      _deletions ??= AccountDeletionCoordinator(directory);
      await _deletions!.purgePendingLocal();
      if (environment.hasSupabase) {
        await Supabase.initialize(
          url: environment.supabaseUrl,
          publishableKey: environment.supabaseKey,
          authOptions: FlutterAuthClientOptions(
            localStorage: SecureAuthStorage(
              supabaseUrl: environment.supabaseUrl,
            ),
            detectSessionInUri: false,
          ),
        );
        nextAuth = SupabaseAuthRepository(Supabase.instance.client);
      } else {
        next = AppController(
          FileAppStore(File('${directory.path}/hamtdaa.json')),
        );
        await next.load();
      }
      if (!mounted) {
        next?.dispose();
        await nextAuth?.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _authRepository = nextAuth;
      });
    } catch (_) {
      next?.dispose();
      await nextAuth?.dispose();
      if (mounted) setState(() => _failed = true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _initializeAccount(AccountScope scope) async {
    final client = Supabase.instance.client;
    final account = SupabaseAccountRepository(client);
    Future<dynamic> rpc(String name) async {
      final refreshed = await client.auth.getSession();
      if (!account.sessionCurrent ||
          account.userId != scope.userId ||
          refreshed == null) {
        throw const AccountOperationException('session_changed');
      }
      return client
          .rpc(name)
          .setHeader('Authorization', 'Bearer ${refreshed.accessToken}');
    }

    await initializeAccountAccess(
      userId: scope.userId,
      sessionCurrent: () =>
          account.sessionCurrent && account.userId == scope.userId,
      pending: () => _deletions!.pending(scope.userId),
      status: () async =>
          Map<String, dynamic>.from(await rpc('hamtdaa_account_status') as Map),
      markPending: () => _deletions!.markPending(scope.userId),
      purgeLocal: _deletions!.purgePendingLocal,
      bootstrap: () async {
        await rpc('hamtdaa_bootstrap');
      },
    );
  }

  Future<void> _deleteAccount({
    AppController? controller,
    required String userId,
    int? epoch,
  }) async {
    final current = _authRepository!.current;
    if (!current.isSignedIn ||
        current.userId != userId ||
        (epoch != null && current.epoch != epoch)) {
      throw const AccountOperationException('session_changed');
    }
    await _deletions!.delete(
      repository: SupabaseAccountRepository(Supabase.instance.client),
      freeze: controller?.freezeForAccountDeletion ?? () async {},
      clearReminders: Reminders.instance.clear,
      signOut: _authRepository!.signOut,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_authRepository?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_authRepository != null && _documentsDirectory != null) {
      return CloudAuthGate(
        documentsDirectory: _documentsDirectory!,
        repository: _authRepository!,
        navigatorObservers: [pairRouteObserver],
        accountInitializer: _initializeAccount,
        onResumeAccountDeletion: (scope) =>
            _deleteAccount(userId: scope.userId),
        appBuilder: (controller) {
          final session = _authRepository!.current;
          return AppShell(
            controller: controller,
            session: session,
            onSignOut: _authRepository!.signOut,
            pairRepositoryFactory: () =>
                SupabasePairRepository(Supabase.instance.client),
            contentRepository: SupabaseContentRepository(
              Supabase.instance.client,
            ),
            accountRepository: SupabaseAccountRepository(
              Supabase.instance.client,
            ),
            onDeleteAccount: () => _deleteAccount(
              controller: controller,
              userId: session.userId!,
              epoch: session.epoch,
            ),
          );
        },
      );
    }
    if (_controller != null) return HamtdaaApp(controller: _controller!);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.folder_off_outlined,
                          size: 48,
                          color: AppColors.pink,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _configurationError == null
                              ? 'Мэдээллийг нээж чадсангүй'
                              : 'Нэвтрэлтийн тохиргоо буруу байна',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _configurationError ??
                              'Хадгалсан мэдээллийг өөрчлөөгүй. Дахин оролдоно уу.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Дахин оролдох'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      ),
    );
  }
}

class HamtdaaApp extends StatelessWidget {
  const HamtdaaApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Нандин мөч',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('mn'),
    supportedLocales: const [Locale('mn'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: AppShell(controller: controller),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.session,
    this.onSignOut,
    this.pairRepositoryFactory,
    this.contentRepository,
    this.accountRepository,
    this.onDeleteAccount,
    this.reminderScheduler,
  });
  final AppController controller;
  final AuthSession? session;
  final Future<void> Function()? onSignOut;
  final PairRepository Function()? pairRepositoryFactory;
  final ContentRepository? contentRepository;
  final AccountRepository? accountRepository;
  final Future<void> Function()? onDeleteAccount;
  final ReminderScheduler? reminderScheduler;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  late AppController _reminderController;
  late ReminderScheduler _reminders;
  late VoidCallback _reminderListener;
  late Future<void> Function(List<DateEvent>) _eventsChanged;
  Future<void> Function(List<DateEvent>)? _previousEventsChanged;
  List<(String, DateTime)>? _scheduled;
  int _reminderLifetime = 0, _reminderRevision = 0;
  int _reminderCloudEpoch = 0;
  bool _remindersReady = false, _remindersDisposed = false;
  bool _foreground = true, _changingForeground = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (widget.contentRepository case final repository?) {
      widget.controller.connectCloud(repository);
    }
    _bindReminders();
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.reminderScheduler, widget.reminderScheduler) ||
        oldWidget.session?.scope != widget.session?.scope) {
      _releaseReminders();
      if (widget.contentRepository case final repository?) {
        widget.controller.connectCloud(repository);
      }
      _bindReminders();
    }
  }

  bool _reminderCurrent(int lifetime) =>
      mounted &&
      !_remindersDisposed &&
      lifetime == _reminderLifetime &&
      (widget.accountRepository?.sessionCurrent ?? true);

  void _bindReminders() {
    final lifetime = ++_reminderLifetime;
    _reminderController = widget.controller;
    _reminders = widget.reminderScheduler ?? Reminders.instance;
    _previousEventsChanged = _reminderController.onEventsChanged;
    final previous = _previousEventsChanged;
    _eventsChanged = (events) async {
      if (!_reminderCurrent(lifetime)) return;
      await previous?.call(events);
      if (_reminderCurrent(lifetime)) await _syncReminders(lifetime);
    };
    _reminderController.onEventsChanged = _eventsChanged;
    _reminderCloudEpoch = _reminderController.cloudEpoch;
    _reminderListener = () {
      final invalidated = _reminderCloudEpoch != _reminderController.cloudEpoch;
      _reminderCloudEpoch = _reminderController.cloudEpoch;
      // The normal background transition only hides private projections. A
      // later invalidation (for example an acknowledged unlink) revokes them.
      if (_reminderCurrent(lifetime) &&
          !_foreground &&
          !_changingForeground &&
          invalidated) {
        ++_reminderRevision;
        _scheduled = null;
        unawaited(_reminders.clear().catchError((Object _) {}));
      }
      _refreshReminders(lifetime);
    };
    _reminderController.addListener(_reminderListener);
    unawaited(_initializeReminders(lifetime));
  }

  Future<void> _initializeReminders(int lifetime) async {
    final scheduler = _reminders;
    try {
      // Initialization is silent. The calendar editor requests permission only
      // when the person explicitly saves an event with a reminder.
      await scheduler.initialize();
      if (!_reminderCurrent(lifetime)) return;
      await scheduler.clear();
      if (!_reminderCurrent(lifetime)) return;
      _remindersReady = true;
      await _syncReminders(lifetime);
    } catch (_) {
      if (_reminderCurrent(lifetime)) {
        _reminderController.reminderError = 'Сануулгыг тохируулж чадсангүй.';
      }
    }
  }

  void _refreshReminders(int lifetime) {
    unawaited(
      _syncReminders(lifetime).catchError((Object _) {
        if (_reminderCurrent(lifetime)) {
          _reminderController.reminderError = 'Сануулгыг тохируулж чадсангүй.';
        }
      }),
    );
  }

  Future<void> _syncReminders(int lifetime) async {
    if (!_reminderCurrent(lifetime) || !_remindersReady || !_foreground) return;
    final controller = _reminderController;
    final notices = <ReminderNotice>[
      for (final event in controller.data.events)
        if (event.reminderMinutes > 0 &&
            !controller.isPartnerItem(event.id) &&
            (!event.shared ||
                (controller.hasRemoteItem(event.id) &&
                    controller.consentState(event.id) == 'accepted')))
          ReminderNotice(
            id: event.id,
            at: event.startsAt.subtract(
              Duration(minutes: event.reminderMinutes),
            ),
          ),
    ];
    final signature = notices.map((notice) => (notice.id, notice.at)).toList();
    if (_scheduled != null &&
        signature.length == _scheduled!.length &&
        Iterable<int>.generate(
          signature.length,
        ).every((i) => signature[i] == _scheduled![i])) {
      return;
    }
    final revision = ++_reminderRevision;
    final scheduler = _reminders;
    _scheduled = null;
    // Revoke obsolete dates before permission lookup can await native work.
    await scheduler.clear();
    if (!_reminderCurrent(lifetime) ||
        revision != _reminderRevision ||
        !_foreground) {
      return;
    }
    final permitted = await scheduler.hasPermission();
    if (!_reminderCurrent(lifetime) ||
        revision != _reminderRevision ||
        !_foreground) {
      return;
    }
    if (permitted) {
      await scheduler.syncNotices(notices);
    } else {
      await scheduler.clear();
    }
    if (_reminderCurrent(lifetime) && revision == _reminderRevision) {
      _scheduled = permitted ? signature : null;
    }
  }

  void _releaseReminders() {
    ++_reminderLifetime;
    ++_reminderRevision;
    _remindersReady = false;
    _scheduled = null;
    _reminderController.removeListener(_reminderListener);
    if (identical(_reminderController.onEventsChanged, _eventsChanged)) {
      _reminderController.onEventsChanged = _previousEventsChanged;
    }
    // clear() invalidates the native batch immediately and queues cancellation
    // ahead of any schedules created by the next account's shell.
    unawaited(_reminders.clear().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) ++_reminderRevision;
    _changingForeground = true;
    try {
      widget.controller.setCloudForeground(_foreground);
    } finally {
      _changingForeground = false;
    }
    if (_foreground) {
      _scheduled = null;
      _refreshReminders(_reminderLifetime);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remindersDisposed = true;
    _releaseReminders();
    widget.controller.setCloudForeground(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: IndexedStack(
            index: _tab,
            children: [
              HomeScreen(
                controller: widget.controller,
                onTab: (tab) => setState(() => _tab = tab),
              ),
              CalendarScreen(controller: widget.controller),
              MemoriesScreen(controller: widget.controller),
              GiftsScreen(controller: widget.controller),
              ProfileScreen(
                controller: widget.controller,
                session: widget.session,
                onSignOut: widget.onSignOut,
                pairRepositoryFactory: widget.pairRepositoryFactory,
                onExportData: (context) => shareAccountExport(
                  context,
                  widget.controller,
                  repository: widget.accountRepository,
                ),
                onDeleteAccount: widget.onDeleteAccount,
              ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Нүүр',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Хуанли',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Дурсамж',
          ),
          NavigationDestination(
            icon: Icon(Icons.card_giftcard_outlined),
            selectedIcon: Icon(Icons.card_giftcard_rounded),
            label: 'Бэлэг',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Бид',
          ),
        ],
      ),
    ),
  );
}
