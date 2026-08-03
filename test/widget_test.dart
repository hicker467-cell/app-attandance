import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_flutter_app/main.dart';

void main() {
  testWidgets('StudentApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
