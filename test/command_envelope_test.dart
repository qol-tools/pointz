import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointz/services/pairing/byte_codec.dart';
import 'package:pointz/services/pairing/command_envelope.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final deviceId = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
  final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i + 100));
  const command = {'type': 'MouseMove', 'x': 1.5, 'y': -2.0};

  test('seals a command into the v3 envelope shape', () async {
    final envelope = await CommandEnvelope.seal(
      key: key,
      deviceId: deviceId,
      command: command,
      sentAtMs: 1700000000123,
      nonce: nonce,
    );

    expect(envelope['version'], 3);
    expect(envelope['sent_at_ms'], 1700000000123);
    expect(envelope['device_id'], encodeBase64Url(deviceId));
    expect(envelope['nonce'], encodeBase64Url(nonce));
    expect(tryDecodeBase64Url(envelope['payload'])!.length, greaterThan(16));
  });

  test('decrypts back with the same key and associated data', () async {
    final envelope = await CommandEnvelope.seal(
      key: key,
      deviceId: deviceId,
      command: command,
      sentAtMs: 1700000000123,
      nonce: nonce,
    );

    final opened = await CommandEnvelope.open(key: key, envelope: envelope);

    expect(opened, command);
  });

  test('fails to decrypt when sent_at_ms is altered', () async {
    final envelope = await CommandEnvelope.seal(
      key: key,
      deviceId: deviceId,
      command: command,
      sentAtMs: 1700000000123,
      nonce: nonce,
    );
    envelope['sent_at_ms'] = 1700000000124;

    expect(
        CommandEnvelope.open(key: key, envelope: envelope), throwsA(anything));
  });

  test('builds associated data as version, big endian time, device id', () {
    final aad = CommandEnvelope.associatedData(deviceId, 0x0102030405060708);

    expect(aad.sublist(0, 9), [3, 1, 2, 3, 4, 5, 6, 7, 8]);
    expect(aad.sublist(9), deviceId);
  });
}
