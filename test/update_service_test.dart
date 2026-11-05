import 'dart:io';

import 'package:bienhypermed/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('orders numerically, not lexically', () {
      expect(compareVersions('1.10.0', '1.9.3'), greaterThan(0));
      expect(compareVersions('1.2.0', '1.2.1'), lessThan(0));
      expect(compareVersions('2.0.0', '2.0.0'), 0);
    });
    test('ignores build/suffix and pads missing parts', () {
      expect(compareVersions('1.4.0+12', '1.4.0'), 0);
      expect(compareVersions('1.4', '1.4.0'), 0);
      expect(compareVersions('1.4.1-beta', '1.4.0'), greaterThan(0));
    });
  });

  group('UpdateManifest', () {
    final json = {
      'version': '1.4.0',
      'min_version': '1.2.0',
      'notes': 'Faster lists',
      'platforms': {
        'windows': {'url': 'https://x/Hypermed-Setup-1.4.0.exe', 'sha256': 'ABC', 'size': 10},
      },
    };
    test('picks the current platform asset and lowercases the hash', () {
      final m = UpdateManifest.fromJson(json, 'windows');
      expect(m.version, '1.4.0');
      expect(m.minVersion, '1.2.0');
      expect(m.asset!.sha256, 'abc');
      expect(m.asset!.size, 10);
    });
    test('no asset for a platform the release does not ship', () {
      expect(UpdateManifest.fromJson(json, 'linux').asset, isNull);
    });
  });

  test('UpdateMode.parse round-trips and rejects junk', () {
    for (final m in UpdateMode.values) {
      expect(UpdateMode.parse(m.name), m);
    }
    expect(UpdateMode.parse('user'), isNull);
    expect(UpdateMode.parse(null), isNull);
  });

  // test/fixtures/latest.json(.sig) signed with the real release key by
  // tool/sign_update_manifest.py — proves the Python signer and the Dart
  // verifier agree byte-for-byte.
  group('manifest signature', () {
    final manifest = File('test/fixtures/latest.json').readAsBytesSync();
    final sig = File('test/fixtures/latest.json.sig').readAsStringSync();

    test('accepts the pipeline-signed feed', () async {
      expect(await verifyManifestSignature(manifest, sig), isTrue);
    });
    test('rejects a feed changed by one byte', () async {
      final tampered = List<int>.of(manifest)..[10] ^= 1;
      expect(await verifyManifestSignature(tampered, sig), isFalse);
    });
    test('rejects a missing/garbage signature', () async {
      expect(await verifyManifestSignature(manifest, ''), isFalse);
      expect(await verifyManifestSignature(manifest, 'not-base64!!'), isFalse);
    });
    test('rejects a signature from an untrusted key', () async {
      expect(await verifyManifestSignature(manifest, sig,
          keys: const ['11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=']), isFalse);
    });
  });

  group('moveIntoPlace', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('upd'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('replaces a leftover package of the same name', () async {
      final part = File('${dir.path}/Setup.exe.part')..writeAsStringSync('new');
      final target = File('${dir.path}/Setup.exe')..writeAsStringSync('old');
      await moveIntoPlace(part, target, delay: Duration.zero);
      expect(target.readAsStringSync(), 'new');
      expect(part.existsSync(), isFalse);
    });

    test('gives up with the rename error after its retries', () async {
      final part = File('${dir.path}/Setup.exe.part')..writeAsStringSync('new');
      final target = File('${dir.path}/Setup.exe');
      Directory(target.path).createSync(); // can be neither renamed onto nor copied to
      await expectLater(moveIntoPlace(part, target, attempts: 3, delay: Duration.zero),
          throwsA(isA<FileSystemException>()));
      expect(part.existsSync(), isTrue);
    });
  });

  // Regression: cleanup ran before the move and deleted the .part itself.
  test('finishDownload keeps the new package and drops old ones', () async {
    final dir = Directory.systemTemp.createTempSync('upd');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Hypermed-Setup-1.1.3.exe').writeAsStringSync('old');
    File('${dir.path}/pending.json').writeAsStringSync('{}');
    final part = File('${dir.path}/Hypermed-Setup-1.1.5.exe.part')..writeAsStringSync('new');
    final pkg = File('${dir.path}/Hypermed-Setup-1.1.5.exe');

    await finishDownload(part, pkg);

    expect(pkg.readAsStringSync(), 'new');
    expect(dir.listSync().map((e) => e.uri.pathSegments.last).toSet(), {'Hypermed-Setup-1.1.5.exe', 'pending.json'});
  });
}
