/// A letter on the Hypermed letterhead (Letters screen).
class Letter {
  const Letter({
    required this.id, required this.referenceNumber, required this.letterDate, required this.recipient,
    required this.subject, required this.body, this.signatoryId, this.signatoryName, this.signatoryHasSignature = false,
    this.signatoryPosition, this.signedAt, this.includeStamp = false, this.createdByName,
    this.canEdit = false, this.canSign = false,
  });

  final int id;
  final String referenceNumber;
  final DateTime letterDate;
  final String recipient, subject, body;
  final int? signatoryId;
  final String? signatoryName, signatoryPosition, createdByName;
  final bool signatoryHasSignature, includeStamp, canEdit, canSign;
  final DateTime? signedAt;

  bool get isSigned => signedAt != null;
  /// First line of the recipient block ("The Director").
  String get recipientFirstLine => recipient.split('\n').first.trim();

  factory Letter.fromJson(Map<String, dynamic> j) {
    final s = j['signatory'] as Map?;
    return Letter(
      id: (j['id'] as num).toInt(),
      referenceNumber: j['reference_number'] as String? ?? '',
      letterDate: DateTime.tryParse(j['letter_date'] as String? ?? '') ?? DateTime.now(),
      recipient: j['recipient'] as String? ?? '',
      subject: j['subject'] as String? ?? '',
      body: j['body'] as String? ?? '',
      signatoryId: (s?['id'] as num?)?.toInt(),
      signatoryName: s?['name'] as String?,
      signatoryHasSignature: s?['has_signature'] == true,
      signatoryPosition: j['signatory_position'] as String?,
      signedAt: DateTime.tryParse(j['signed_at'] as String? ?? '')?.toLocal(),
      includeStamp: j['include_stamp'] == true,
      createdByName: (j['created_by'] as Map?)?['name'] as String?,
      canEdit: j['can_edit'] == true,
      canSign: j['can_sign'] == true,
    );
  }
}

class LetterSignatory {
  const LetterSignatory({required this.id, required this.name, this.position, this.hasSignature = false});
  final int id;
  final String name;
  final String? position;
  final bool hasSignature;
  factory LetterSignatory.fromJson(Map<String, dynamic> j) => LetterSignatory(
    id: (j['id'] as num).toInt(), name: j['name'] as String? ?? '', position: j['position'] as String?,
    hasSignature: j['has_signature'] == true);
}
