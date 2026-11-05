import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/labeled_field.dart';

// Dropdown, date and static boxes must be exactly as tall as the text field
// beside them — on desktop (compact density, 37px) and mobile (45px) alike.
void main() {
  Future<Map<String, double>> heights(WidgetTester tester, {bool dense = false}) async {
    final row = Column(children: [
      LabeledTextField(label: '', controller: TextEditingController(), hint: 'x'),
      DropdownFieldBox<int>(key: const Key('dd'), value: 1, items: const [DropdownMenuItem(value: 1, child: Text('One'))], onChanged: (_) {}),
      LabeledDateField(key: const Key('date'), label: 'Date', date: null, onTap: () {}),
      const LabeledStaticField(key: Key('static'), label: 'Static', value: 'v'),
    ]);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.hypermed(), home: Scaffold(body: dense ? DenseFields(child: row) : row)));
    double boxOf(String key) => tester.getSize(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Container)).first).height;
    return {
      'text': tester.getSize(find.byType(TextField).first).height,
      'dropdown': tester.getSize(find.byKey(const Key('dd'))).height,
      'date': boxOf('date'),
      'static': boxOf('static'),
    };
  }

  testWidgets('boxes match the text field on desktop', (tester) async {
    final h = await heights(tester);
    expect(h['text'], 37);
    expect(h.values.toSet(), {37.0}, reason: '$h');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('boxes match the text field on mobile', (tester) async {
    final h = await heights(tester);
    expect(h['text'], 45);
    expect(h.values.toSet(), {45.0}, reason: '$h');
  });

  testWidgets('dense filter rows stay 28px', (tester) async {
    final h = await heights(tester, dense: true);
    expect(h['text'], 28);
    expect(h['dropdown'], 28);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
