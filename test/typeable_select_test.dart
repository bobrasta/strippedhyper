import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/app_dropdown.dart';
import 'package:bienhypermed/widgets/common/labeled_field.dart';

// Every select is typeable: click opens the whole list, typing narrows it,
// Enter picks the top match, clicking away keeps the old value.
void main() {
  const regions = ['Arusha', 'Dar es Salaam', 'Dodoma', 'Mwanza', 'Tanga'];

  Future<List<String?>> pump(WidgetTester tester) async {
    final picked = <String?>[];
    String? value = 'Arusha';
    await tester.pumpWidget(MaterialApp(theme: AppTheme.hypermed(), home: Scaffold(
      body: StatefulBuilder(builder: (context, setState) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          LabeledDropdown<String>(
            label: 'Region', value: value!, items: regions, displayBuilder: (r) => r,
            onChanged: (v) => setState(() { value = v; picked.add(v); }),
          ),
          const SizedBox(height: 300),
          const Text('elsewhere'),
        ]),
      )),
    )));
    return picked;
  }

  Finder row(String label) => find.descendant(of: find.byType(ListView), matching: find.text(label));

  testWidgets('click opens every option; typing narrows; Enter picks the top match', (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    for (final r in regions) {
      expect(row(r), findsOneWidget, reason: r);
    }

    await tester.enterText(find.byType(TextField), 'do');
    await tester.pumpAndSettle();
    expect(row('Dodoma'), findsOneWidget);
    expect(row('Mwanza'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['Dodoma']);
    expect(find.byType(ListView), findsNothing);
    expect(find.widgetWithText(TextField, 'Dodoma'), findsOneWidget);
  });

  testWidgets('clicking an option picks it', (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tan');
    await tester.pumpAndSettle();
    await tester.tap(row('Tanga'));
    await tester.pumpAndSettle();
    expect(picked, ['Tanga']);
  });

  testWidgets('clicking away without picking keeps the old value', (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'mw');
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('elsewhere')));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.widgetWithText(TextField, 'Arusha'), findsOneWidget);
  });

  testWidgets('multi-select filters its checklist while typing', (tester) async {
    var values = <int>{};
    await tester.pumpWidget(MaterialApp(theme: AppTheme.hypermed(), home: Scaffold(
      body: StatefulBuilder(builder: (context, setState) => Padding(
        padding: const EdgeInsets.all(24),
        child: AppMultiSelectField<int>(
          hint: 'All categories', values: values,
          items: [for (var i = 0; i < regions.length; i++) AppSelectItem(value: i, label: regions[i])],
          onChanged: (v) => setState(() => values = v),
        ),
      )),
    )));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dar');
    await tester.pumpAndSettle();
    expect(row('Dar es Salaam'), findsOneWidget);
    expect(row('Arusha'), findsNothing);
    await tester.tap(row('Dar es Salaam'));
    await tester.pumpAndSettle();
    expect(values, {1});
  });
}
