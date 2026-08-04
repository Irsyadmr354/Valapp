import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/shared/widgets/countdown_timer.dart';

void main() {
  testWidgets('zero countdown expires once after mounting', (tester) async {
    var expirationCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: CountdownTimer(
        remainingSeconds: 0,
        onExpired: () => expirationCount++,
      ),
    ));

    await tester.pump();

    expect(expirationCount, 1);
    expect(find.text('00:00:00'), findsOneWidget);
    await tester.pump();
    expect(expirationCount, 1);
  });
}
