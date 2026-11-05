import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The server's certificates come from Let's Encrypt, which chains to ISRG
/// Root X1. Windows keeps only some root certificates locally and fetches the
/// rest when a browser first needs them — but a Flutter app doesn't trigger
/// that, so on a fresh or rarely-updated PC (an HP tablet, 2026-10-26) the
/// secure connection failed and login said "Login failed. Please try again
/// later." Trusting the bundled ISRG roots as well (on top of the system
/// ones) makes the connection work regardless.
Future<void> installBundledRootCertificates() async {
  if (kIsWeb) return;
  for (final asset in const ['assets/certs/isrg_root_x1.pem', 'assets/certs/isrg_root_x2.pem']) {
    try {
      final pem = await rootBundle.load(asset);
      SecurityContext.defaultContext.setTrustedCertificatesBytes(pem.buffer.asUint8List());
    } on TlsException catch (e) {
      // Already trusted (e.g. present in the system store) — nothing to do.
      dev.log('root $asset: ${e.message}', name: 'TLS');
    } catch (e) {
      dev.log('root $asset not loaded: $e', name: 'TLS');
    }
  }
}
