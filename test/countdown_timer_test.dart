import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/shared/widgets/countdown_timer.dart';

void main() {
  testWidgets('deadline identity resets an otherwise equal countdown',
      (tester) async {
    var identity = 'shop-a';
    var expirations = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return CountdownTimer(
          remainingSeconds: 0,
          deadlineIdentity: identity,
          onExpired: () => expirations++,
        );
      }),
    ));

    await tester.pump();
    expect(expirations, 1);

    rebuild(() => identity = 'shop-b');
    await tester.pump();
    await tester.pump();
    expect(expirations, 2);
  });
}
