// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:eventchain/main.dart';

void main() {
  testWidgets('App renders with bottom navigation', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: EventChainApp()));

    // Verify that the bottom navigation bar is present with expected labels.
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);

    // Verify initial tab is Events (look for navigation indicator)
    expect(find.byIcon(Icons.event), findsOneWidget);
  });
}