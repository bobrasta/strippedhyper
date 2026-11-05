// Turns HTML that some sources (NeST clarifications, pasted Word/Outlook
// text) send in plain-text fields into readable plain text: paragraphs and
// <br> become line breaks, list items become "• " / "1. " lines, every other
// tag (including broken ones like `<spanstyle='…'>` or `<o:p>`) is dropped
// and entities are decoded. Text with no markup is returned unchanged.

final _looksLikeHtml = RegExp(r'</?[a-zA-Z][a-zA-Z0-9:]*(\s[^>]*)?/?>|&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);');
final _dropBlocks = RegExp(r'<(head|style|script|xml)\b[^>]*>[\s\S]*?</\1\s*>', caseSensitive: false);
final _comments = RegExp(r'<!--[\s\S]*?-->');
final _tag = RegExp(r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9:]*)[^>]*>');
final _strayTag = RegExp(r'<\s*/?\s*[a-zA-Z!][^<>]*$');
final _entity = RegExp(r'&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);');

const _blockTags = {
  'p', 'div', 'tr', 'table', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'section', 'article', 'header', 'footer', 'pre', 'hr',
};

const _named = {
  'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'ndash': '–', 'mdash': '—', 'hellip': '…', 'lsquo': '‘', 'rsquo': '’',
  'ldquo': '“', 'rdquo': '”', 'bull': '•', 'middot': '·', 'copy': '©',
  'reg': '®', 'trade': '™', 'deg': '°', 'times': '×', 'plusmn': '±',
};

String _decode(String s) => s.replaceAllMapped(_entity, (m) {
  final e = m[1]!;
  int? code;
  if (e.startsWith('#x') || e.startsWith('#X')) {
    code = int.tryParse(e.substring(2), radix: 16);
  } else if (e.startsWith('#')) {
    code = int.tryParse(e.substring(1));
  }
  if (code != null) {
    if (code == 0xA0) return ' ';
    return code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : '';
  }
  return _named[e.toLowerCase()] ?? m[0]!;
});

/// Plain text for [input]; `null` stays `null`.
String? htmlToPlainTextOrNull(String? input) => input == null ? null : htmlToPlainText(input);

/// Plain text for [input] (see the file comment).
String htmlToPlainText(String input) {
  if (!_looksLikeHtml.hasMatch(input)) return input;

  var s = input.replaceAll(_comments, '').replaceAll(_dropBlocks, '');
  // Source line breaks inside HTML are just whitespace.
  s = s.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');

  // Walk the tags so ordered lists can be numbered. [fresh] is true at the
  // start of a line (or right after a list marker), where a block tag adds
  // no extra break — so `<li><p>…` stays on one line and `<p>a</p><p>b</p>`
  // gives two lines, not a blank line between.
  final out = StringBuffer();
  final lists = <int?>[]; // null = <ul>, n = next number of an <ol>
  var fresh = true;
  void text(String t) {
    if (t.trim().isEmpty && fresh) return;
    out.write(t);
    if (t.isNotEmpty) fresh = false;
  }
  void lineBreak({bool force = false}) {
    if (fresh && !force) return;
    out.write('\n');
    fresh = true;
  }
  var at = 0;
  for (final m in _tag.allMatches(s)) {
    text(s.substring(at, m.start));
    at = m.end;
    final closing = m[1] == '/';
    final name = m[2]!.toLowerCase();
    if (name == 'br') {
      lineBreak(force: true);
    } else if (name == 'li') {
      lineBreak();
      if (!closing) {
        var bullet = '• ';
        if (lists.isNotEmpty && lists.last != null) {
          bullet = '${lists.last}. ';
          lists[lists.length - 1] = lists.last! + 1;
        }
        out.write(bullet);
      }
    } else if (name == 'ul' || name == 'ol') {
      if (closing) {
        if (lists.isNotEmpty) lists.removeLast();
      } else {
        final start = RegExp(r'''start\s*=\s*["']?(\d+)''').firstMatch(m[0]!);
        lists.add(name == 'ol' ? int.tryParse(start?[1] ?? '') ?? 1 : null);
      }
      lineBreak();
    } else if (name == 'td' || name == 'th') {
      if (closing) text('  ');
    } else if (_blockTags.contains(name)) {
      lineBreak();
    }
  }
  text(s.substring(at));

  s = out.toString().replaceAll(_strayTag, '');
  s = _decode(s);

  // Tidy whitespace: no runs of spaces, no blank-line pile-ups.
  s = s.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ');
  s = s.replaceAll(RegExp(r' *\n *'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
