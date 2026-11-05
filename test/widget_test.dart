import 'package:flutter_test/flutter_test.dart';
import 'package:bienhypermed/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HypermedApp());
    expect(find.byType(HypermedApp), findsOneWidget);
  });
}
