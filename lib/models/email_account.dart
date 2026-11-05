class EmailAccount {
  final int    id;
  final String label;
  final String fromName;
  final String fromEmail;
  final String username;
  final String imapHost;
  final int    imapPort;
  final String imapEncryption;
  final String smtpHost;
  final int    smtpPort;
  final String smtpEncryption;
  final bool   isDefault;

  const EmailAccount({
    required this.id,
    required this.label,
    required this.fromName,
    required this.fromEmail,
    required this.username,
    required this.imapHost,
    required this.imapPort,
    required this.imapEncryption,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpEncryption,
    required this.isDefault,
  });

  factory EmailAccount.fromJson(Map<String, dynamic> j) => EmailAccount(
    id:             (j['id'] as num).toInt(),
    label:          j['label']           as String? ?? 'Email Account',
    fromName:       j['from_name']       as String? ?? '',
    fromEmail:      j['from_email']      as String? ?? '',
    username:       j['username']        as String? ?? '',
    imapHost:       j['imap_host']       as String? ?? '',
    imapPort:       (j['imap_port']      as num?  ?? 993).toInt(),
    imapEncryption: j['imap_encryption'] as String? ?? 'ssl',
    smtpHost:       j['smtp_host']       as String? ?? '',
    smtpPort:       (j['smtp_port']      as num?  ?? 465).toInt(),
    smtpEncryption: j['smtp_encryption'] as String? ?? 'ssl',
    isDefault:      j['is_default']      as bool?  ?? false,
  );
}
