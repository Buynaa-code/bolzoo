import 'dart:io';
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
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  AppController? _controller;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    AppController? next;
    try {
      final directory = await getApplicationDocumentsDirectory();
      next = AppController(
        FileAppStore(File('${directory.path}/hamtdaa.json')),
      );
      await next.load();
      if (!mounted) {
        next.dispose();
        return;
      }
      setState(() => _controller = next);
    } catch (_) {
      next?.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                        const Text(
                          'Мэдээллийг нээж чадсангүй',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        const Text(
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
    title: 'Хамтдаа',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('mn'),
    supportedLocales: const [Locale('mn'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: AppShell(controller: controller),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
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
              ProfileScreen(controller: widget.controller),
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
