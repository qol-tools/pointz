import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'byte_codec.dart';

class CommandEnvelope {
  static const int version = 3;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int keyLength = 32;

  static Uint8List associatedData(Uint8List deviceId, int sentAtMs) =>
      concatBytes([
        const [version],
        unixMillisBigEndian(sentAtMs),
        deviceId,
      ]);

  static Future<Map<String, dynamic>> seal({
    required Uint8List key,
    required Uint8List deviceId,
    required Map<String, dynamic> command,
    required int sentAtMs,
    required Uint8List nonce,
  }) async {
    final box = await Chacha20.poly1305Aead().encrypt(
      utf8.encode(jsonEncode(command)),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: associatedData(deviceId, sentAtMs),
    );
    return {
      'version': version,
      'device_id': encodeBase64Url(deviceId),
      'sent_at_ms': sentAtMs,
      'nonce': encodeBase64Url(nonce),
      'payload': encodeBase64Url(concatBytes([box.cipherText, box.mac.bytes])),
    };
  }

  static Future<Map<String, dynamic>> open({
    required Uint8List key,
    required Map<String, dynamic> envelope,
  }) async {
    final deviceId =
        tryDecodeBase64Url(envelope['device_id'], expectedLength: 16)!;
    final nonce =
        tryDecodeBase64Url(envelope['nonce'], expectedLength: nonceLength)!;
    final payload = tryDecodeBase64Url(envelope['payload'])!;
    final sentAtMs = envelope['sent_at_ms'] as int;
    final split = payload.length - tagLength;
    final box = SecretBox(
      payload.sublist(0, split),
      nonce: nonce,
      mac: Mac(payload.sublist(split)),
    );
    final clear = await Chacha20.poly1305Aead().decrypt(
      box,
      secretKey: SecretKey(key),
      aad: associatedData(deviceId, sentAtMs),
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }
}
