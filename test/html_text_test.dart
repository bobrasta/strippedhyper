import 'package:flutter_test/flutter_test.dart';
import 'package:bienhypermed/utils/html_text.dart';

void main() {
  test('plain text is left alone', () {
    expect(htmlToPlainText('Extension granted'), 'Extension granted');
    expect(htmlToPlainText('Qty < 5 and > 2'), 'Qty < 5 and > 2');
  });

  test('div / br become line breaks', () {
    expect(
      htmlToPlainText('Hello PE,<div><br></div><div>We kindly request you to extend the submission deadline</div>'),
      'Hello PE,\n\nWe kindly request you to extend the submission deadline',
    );
  });

  test('ordered list items are numbered, inline tags dropped', () {
    final s = htmlToPlainText(
      '<p data-pm-slice="1 1 []"><em>WLAN equipment,</em> includes CCTV.</p><p>Kindly clarify:</p>'
      '<ol data-spread="false" start="1"><li><p>Provide a <strong>BOQ</strong>.</p></li><li><p>Confirm 68 items.</p></li></ol>'
      '<p>Thanks.</p>');
    expect(s, 'WLAN equipment, includes CCTV.\nKindly clarify:\n1. Provide a BOQ.\n2. Confirm 68 items.\nThanks.');
  });

  test('broken Word markup and entities', () {
    final s = htmlToPlainText(
      "Dear PE,<br>Item <span style=\"font-family: Roboto;\">9. WLAN</span><spanstyle='letter-spacing:1.45pt'> access"
      "</spanstyle='letter-spacing:1.45pt'> network<o:p></o:p> &amp; &ldquo;C38&rdquo;&nbsp;&#8211; ok</h5>");
    expect(s, 'Dear PE,\nItem 9. WLAN access network & “C38” – ok');
  });

  test('a tag cut off at the end is removed', () {
    expect(htmlToPlainText('<p>Quantity of 68 sets.</p><p'), 'Quantity of 68 sets.');
  });
}
