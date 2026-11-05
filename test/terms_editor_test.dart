import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/sales/terms_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TermsController.debugDefaults = [
      (label: 'Payment', text: '100% advance payment'),
      (label: 'Delivery', text: '1 to 2 days'),
      (label: 'Installation and training', text: 'As agreed.'),
    ];
  });
  tearDown(() { TermsController.debugDefaults = null; });

  testWidgets('defaults are placeholders; a saved term fills its field; blanks go back as blank', (tester) async {
    final ctrl = TermsController();
    await tester.runAsync(() => ctrl.load([(label: 'Delivery', text: 'Within 5 days')]));
    tester.view.physicalSize = const Size(620, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(15), child: TermsEditor(controller: ctrl)))));

    expect(find.text('100% advance payment'), findsOneWidget); // placeholder
    expect(find.text('Within 5 days'), findsOneWidget);        // this sale's own
    await tester.enterText(find.byType(TextField).first, '50% now, 50% on delivery');

    expect(ctrl.toJson(), [
      {'label': 'Payment', 'text': '50% now, 50% on delivery'},
      {'label': 'Delivery', 'text': 'Within 5 days'},
      {'label': 'Installation and training', 'text': ''},
    ]);
    expect(tester.takeException(), isNull);
    ctrl.dispose();
  });
}
