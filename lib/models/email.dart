/// A file on a received or sent email, kept on the server
/// (GET /emails/{email}/attachments/{id}).
class EmailAttachment {
  const EmailAttachment({required this.id, required this.filename, required this.size, this.mimeType});
  final int id;
  final String filename;
  final int size;
  final String? mimeType;

  String get extension {
    final dot = filename.lastIndexOf('.');
    return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  }

  bool get isPdf => extension == 'pdf' || mimeType == 'application/pdf';
  bool get isImage =>
      (mimeType ?? '').startsWith('image/') || const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(extension);

  String get sizeLabel => size >= 1024 * 1024
      ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(size / 1024).ceil()} KB';

  factory EmailAttachment.fromJson(Map<String, dynamic> j) => EmailAttachment(
    id: (j['id'] as num).toInt(),
    filename: j['filename'] as String? ?? 'attachment',
    size: (j['size'] as num?)?.toInt() ?? 0,
    mimeType: j['mime_type'] as String?,
  );
}

class Email {
  final int     id;
  final String  from;
  final String  fromEmail;
  final String  to;
  final String? cc;
  final String? bcc;
  final String  subject;
  final String  body;     // always plain text
  /// The message as sent (style/script already stripped by the API), for
  /// the formatted reading view; null for plain-text mail.
  final String? bodyHtml;
  final String  preview;
  final String  folder;
  final String? label;
  final bool    isRead;
  final bool    isFlagged;
  final DateTime createdAt;
  final bool    hasAttachments;
  /// Only on a single email (GET /emails/{id}); lists carry [hasAttachments].
  final List<EmailAttachment> attachments;

  const Email({
    required this.id,
    required this.from,
    required this.fromEmail,
    required this.to,
    this.cc,
    this.bcc,
    required this.subject,
    required this.body,
    this.bodyHtml,
    required this.preview,
    required this.folder,
    this.label,
    required this.isRead,
    required this.isFlagged,
    required this.createdAt,
    this.hasAttachments = false,
    this.attachments = const [],
  });

  String get initials {
    final parts = from.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return from.isNotEmpty ? from[0].toUpperCase() : '?';
  }

  /// Folder kinds the screen treats differently.
  bool get inSpam  => _leaf(folder, const {'junk', 'spam', 'junk e-mail', 'junk email', 'junk mail', 'bulk mail'});
  bool get inTrash => _leaf(folder, const {'trash', 'deleted', 'deleted items', 'deleted messages', 'bin'});
  bool get inArchive => _leaf(folder, const {'archive', 'archives'});

  static bool _leaf(String path, Set<String> names) =>
      names.contains(path.split(RegExp(r'[./]')).last.trim().toLowerCase());

  /// "Tue, 3 Nov 2026, 14:05" — the reading view's full date.
  String get fullDateLabel {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = createdAt;
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}, '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get timeLabel {
    final now  = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 60 && diff.inMinutes >= 0) return '${diff.inMinutes}m';
    final days = dayGroupOffset;
    if (days == 0) {
      final h = createdAt.hour.toString().padLeft(2, '0');
      final m = createdAt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (days == 1) return 'Yesterday';
    if (days > 1 && days < 7) {
      const names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return names[createdAt.weekday - 1];
    }
    return createdAt.year == now.year
        ? '${createdAt.day}/${createdAt.month}'
        : '${createdAt.day}/${createdAt.month}/${createdAt.year % 100}';
  }

  /// Calendar days between today and this email (0 = today).
  int get dayGroupOffset {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(createdAt.year, createdAt.month, createdAt.day)).inDays;
  }

  /// The list's section: Today, Yesterday, This week, then month by month.
  String get dateGroup {
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'];
    final d = dayGroupOffset;
    if (d <= 0) return 'Today';
    if (d == 1) return 'Yesterday';
    if (d < 7) return 'This week';
    final now = DateTime.now();
    return createdAt.year == now.year
        ? months[createdAt.month - 1]
        : '${months[createdAt.month - 1]} ${createdAt.year}';
  }

  factory Email.fromJson(Map<String, dynamic> j) {
    final rawHtml  = _str(j['body_html']);
    final rawText  = _str(j['body_text']) ?? _str(j['body']) ?? _str(j['content']);
    final body     = rawHtml != null ? _htmlToText(rawHtml) : (rawText ?? '');
    final preview  = _str(j['body_preview']) ?? _str(j['preview']) ?? _makePreview(body);
    final ccStr    = _addrList(j['cc']);
    final bccStr   = _addrList(j['bcc']);
    return Email(
      id:        (j['id'] as num).toInt(),
      from:      _addr(j['from_name'])  ?? _addr(j['from'])  ?? '—',
      fromEmail: _addrEmail(j['from_email']) ?? _addrEmail(j['from']) ?? '',
      to:        _addrList(j['to']),
      cc:        ccStr.isNotEmpty  ? ccStr  : null,
      bcc:       bccStr.isNotEmpty ? bccStr : null,
      subject:   _str(j['subject'])  ?? '(no subject)',
      body:      body,
      bodyHtml:  rawHtml,
      preview:   preview,
      folder:    _str(j['folder'])   ?? 'inbox',
      label:     _str(j['label'])    ?? _str(j['tag']),
      isRead:    j['is_read']    is bool ? j['is_read']    as bool
                                        : j['read']    is bool ? j['read']    as bool : false,
      isFlagged: j['is_flagged'] is bool ? j['is_flagged'] as bool
                                        : j['flagged'] is bool ? j['flagged'] as bool : false,
      createdAt: DateTime.tryParse(_str(j['date']) ?? _str(j['created_at']) ?? '') ?? DateTime.now(),
      hasAttachments: j['has_attachments'] == true,
      attachments: [
        for (final a in (j['attachments'] is List ? j['attachments'] as List : const []))
          EmailAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
    );
  }

  // ── HTML → plain text ────────────────────────────────────────────────────────

  static String _htmlToText(String html) {
    var s = html;

    // 1. Drop entire <head> block (styles, meta, link tags)
    s = s.replaceAll(RegExp(r'<head\b[^>]*>[\s\S]*?</head>', caseSensitive: false), '');

    // 2. Drop <style> and <script> blocks wherever they appear
    s = s.replaceAll(RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false), '');

    // 3. Drop known antivirus / mailer footers by element id
    s = s.replaceAll(RegExp(
      r'<[a-z]+[^>]*\bid="DAB4FAD8[^"]*"[^>]*>[\s\S]*?</[a-z]+>',
      caseSensitive: false), '');

    // 4. Drop HubSpot "Create Your Own Free Signature" table and everything after
    final hubIdx = s.indexOf('Create Your Own Free Signature');
    if (hubIdx != -1) {
      // Walk back to the opening <table before it
      final tableOpen = s.lastIndexOf(RegExp(r'<table', caseSensitive: false), hubIdx);
      if (tableOpen != -1) s = s.substring(0, tableOpen);
    }

    // 5. Drop Quectel / Outlook signature block (div with id="Signature")
    s = s.replaceAll(RegExp(
      r'<div\b[^>]*\bid="Signature"[^>]*>[\s\S]*?</div>',
      caseSensitive: false), '');

    // 6. Collapse block-level tags → newlines
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|div|tr|li|h[1-6]|blockquote)>', caseSensitive: false), '\n');
    // Table cells side by side: "Item  Qty", not "ItemQty".
    s = s.replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), '  ');

    // 7. Strip all remaining tags
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');

    // 8. Decode HTML entities
    s = s
      .replaceAll('&nbsp;',  ' ')
      .replaceAll('&amp;',   '&')
      .replaceAll('&lt;',    '<')
      .replaceAll('&gt;',    '>')
      .replaceAll('&quot;',  '"')
      .replaceAll('&#39;',   "'")
      .replaceAll('&apos;',  "'");

    // 9. Normalise whitespace
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r' *\n *'), '\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return s.trim();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String? _str(dynamic v) {
    if (v == null)   return null;
    if (v is String) return v.isEmpty ? null : v;
    if (v is Map) {
      final t = v['text'], h = v['html'];
      return (t is String && t.isNotEmpty) ? t : (h is String && h.isNotEmpty) ? h : null;
    }
    return null;
  }

  static String? _addr(dynamic v) {
    if (v == null)   return null;
    if (v is String) return v.isEmpty ? null : v;
    if (v is Map) {
      final n = v['name'], e = v['email'];
      return (n is String && n.isNotEmpty) ? n : (e is String && e.isNotEmpty) ? e : null;
    }
    if (v is List)   return v.isNotEmpty ? _addr(v.first) : null;
    return null;
  }

  static String? _addrEmail(dynamic v) {
    if (v == null)   return null;
    if (v is String) return v.isEmpty ? null : v;
    if (v is Map) {
      final e = v['email'], a = v['address'];
      return (e is String && e.isNotEmpty) ? e : (a is String && a.isNotEmpty) ? a : null;
    }
    if (v is List)   return v.isNotEmpty ? _addrEmail(v.first) : null;
    return null;
  }

  static String _addrList(dynamic v) {
    if (v == null)   return '';
    if (v is String) return v;
    if (v is Map)    return _addr(v) ?? _addrEmail(v) ?? '';
    if (v is List) {
      return v
          .map((e) => _addr(e) ?? _addrEmail(e) ?? '')
          .where((s) => s.isNotEmpty)
          .join(', ');
    }
    return v.toString();
  }

  static String _makePreview(String plainText) {
    final clean = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 120 ? '${clean.substring(0, 120)}…' : clean;
  }

  Email copyWith({bool? isRead, bool? isFlagged}) => Email(
    id: id, from: from, fromEmail: fromEmail, to: to, cc: cc, bcc: bcc,
    subject: subject, body: body, bodyHtml: bodyHtml, preview: preview, folder: folder, label: label,
    isRead:    isRead    ?? this.isRead,
    isFlagged: isFlagged ?? this.isFlagged,
    createdAt: createdAt,
    hasAttachments: hasAttachments,
    attachments: attachments,
  );
}
