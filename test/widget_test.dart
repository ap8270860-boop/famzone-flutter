import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famzone/main.dart';

void main() {
  testWidgets('connectivity screen renders with a ping button', (tester) async {
    await tester.pumpWidget(const FamZoneApp());

    expect(find.text('FamZone'), findsOneWidget);
    expect(find.text('API connectivity'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ping the API'), findsOneWidget);
  });
}
