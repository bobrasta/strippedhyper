import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../common/labeled_field.dart';

/// One TERMS & CONDITIONS heading ("Payment", "Delivery", …) and its text.
typedef TermItem = ({String label, String text});

List<TermItem>? termItemsFromJson(dynamic j) => j is List
    ? [for (final t in j.whereType<Map>()) (label: '${t['label']}', text: '${t['text'] ?? ''}')]
    : null;

/// TERMS & CONDITIONS on a sale or quotation. Every company default heading
/// gets a field whose placeholder is the default wording; whatever is typed
/// replaces it on this document only, and a blank field prints the default.
class TermsController {
  TermsController();

  static Future<List<TermItem>>? _defaults;

  @visibleForTesting
  static set debugDefaults(List<TermItem>? v) => _defaults = v == null ? null : Future.value(v);

  /// The company defaults (GET /document-terms), fetched once per session.
  static Future<List<TermItem>> defaults() => _defaults ??= ApiClient.instance.dio
      .get('/document-terms')
      .then((res) => termItemsFromJson(ApiClient.unwrap(res)) ?? <TermItem>[])
      .catchError((Object e) { _defaults = null; throw e; });

  List<TermItem> headings = [];
  final Map<String, TextEditingController> _ctrls = {};

  /// Loads the defaults and fills in [own] — the document's saved terms.
  Future<void> load([List<TermItem>? own]) async {
    try {
      headings = await defaults();
    } catch (_) {
      headings = [];
    }
    // A heading this document has but the defaults no longer do stays editable.
    for (final t in own ?? const <TermItem>[]) {
      if (!headings.any((h) => h.label == t.label)) headings = [...headings, (label: t.label, text: '')];
    }
    for (final h in headings) {
      _ctrls.putIfAbsent(h.label, TextEditingController.new);
    }
    for (final t in own ?? const <TermItem>[]) {
      _ctrls[t.label]!.text = t.text;
    }
  }

  TextEditingController controllerFor(String label) => _ctrls[label]!;

  /// For the API: every heading, blank where the default applies.
  List<Map<String, String>> toJson() => [
    for (final h in headings) {'label': h.label, 'text': _ctrls[h.label]!.text.trim()},
  ];

  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
  }
}

/// The fields for a [TermsController], one per heading, side by side as
/// they print on the PDF.
class TermsEditor extends StatelessWidget {
  const TermsEditor({super.key, required this.controller});
  final TermsController controller;

  @override
  Widget build(BuildContext context) {
    final headings = controller.headings;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Terms & conditions', style: AppTheme.bodyStrong),
      const SizedBox(height: 2),
      Text('Printed on this document. Leave a field empty to use the standard wording shown in it.',
          style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      const SizedBox(height: 10),
      if (headings.isEmpty)
        Text('Standard terms will be printed.', style: AppTheme.bodySub)
      else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, h) in headings.indexed) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: LabeledTextField(
              label: h.label,
              controller: controller.controllerFor(h.label),
              hint: h.text,
              maxLines: 3,
            )),
          ],
        ]),
    ]);
  }
}
