import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/features/pair/pair_screen.dart';

import 'pair_flow_test.dart' show FakePairRepository, pair, snapshot;

void main() {
  testWidgets('sign-out before the next frame cancels connection navigation', (
    tester,
  ) async {
    final repository = FakePairRepository();
    var connected = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [pairRouteObserver],
        home: PairScreen(
          repository: repository,
          onConnected: () => connected++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    repository.current = snapshot(active: pair);
    await tester.tap(find.byKey(const Key('pairRefresh')));
    await tester.idle();
    // The status request finished, but its scheduled navigation must not escape
    // the account boundary if this session is invalidated before the frame.
    repository.events.add(null);
    await tester.pumpAndSettle();
    expect(connected, 0);
    await tester.pumpWidget(const SizedBox());
    expect(repository.disposed, isTrue);
  });

  testWidgets(
    'connection navigation waits for an overlaid dialog and fires once',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final repository = FakePairRepository();
      var connected = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [pairRouteObserver],
          home: PairScreen(
            repository: repository,
            onConnected: () => connected++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dialog = navigator.currentState!.push<void>(
        DialogRoute<void>(
          context: navigator.currentContext!,
          builder: (_) => const AlertDialog(content: Text('Түр цонх')),
        ),
      );
      await tester.pumpAndSettle();
      repository.current = snapshot(active: pair);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Түр цонх'), findsOneWidget);
      expect(connected, 0);

      navigator.currentState!.pop();
      await dialog;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(connected, 1);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(connected, 1);
      await tester.pumpWidget(const SizedBox());
      expect(repository.disposed, isTrue);
    },
  );
}
