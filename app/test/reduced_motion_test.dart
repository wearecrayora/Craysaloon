// DESIGN 13: "reduced-motion path verified; no shimmer". The phone's "remove
// animations" setting reaches Flutter as MediaQuery.disableAnimations; every
// motion primitive must honour it - an entrance shows at once, a press does
// not scale. Each case has its control, so this cannot pass by asserting
// nothing: with animations ON, the same widgets do animate.

import 'package:craysalon/core/ui/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {required bool reduced}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _opacityOf(WidgetTester tester, Finder child) {
  final opacities = tester.widgetList<Opacity>(
    find.ancestor(of: child, matching: find.byType(Opacity)),
  );
  return opacities.fold(1.0, (v, o) => v * o.opacity);
}

void main() {
  testWidgets('reduced motion: something that appears is simply there, on the first frame',
      (tester) async {
    await tester.pumpWidget(_host(const Appear(child: Text('Your bill is ready')), reduced: true));

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(_opacityOf(tester, find.text('Your bill is ready')), 1.0);
  });

  testWidgets('control: with animations on, the same entrance does fade in', (tester) async {
    await tester.pumpWidget(_host(const Appear(child: Text('Your bill is ready')), reduced: false));

    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
    expect(_opacityOf(tester, find.text('Your bill is ready')), lessThan(1.0));
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, find.text('Your bill is ready')), 1.0);
  });

  Future<double> pressedScale(WidgetTester tester, {required bool reduced}) async {
    await tester.pumpWidget(_host(
      Pressable(onTap: () {}, child: const SizedBox(width: 120, height: 48, child: Text('Book'))),
      reduced: reduced,
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Book')));
    await tester.pumpAndSettle();
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    await gesture.up();
    await tester.pumpAndSettle();
    return scale;
  }

  testWidgets('reduced motion: a pressed button does not shrink', (tester) async {
    expect(await pressedScale(tester, reduced: true), 1.0);
  });

  testWidgets('control: with animations on, it does', (tester) async {
    expect(await pressedScale(tester, reduced: false), lessThan(1.0));
  });
}
