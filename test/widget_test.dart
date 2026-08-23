import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famzone/main.dart';

void main() {
  testWidgets('welcome screen shows wordmark, promise and both actions',
      (tester) async {
    await tester.pumpWidget(const SFamilyApp());

    expect(find.text('S'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
  });
}
