import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointz/services/pairing/byte_codec.dart';
import 'package:pointz/services/pairing/spake2_client.dart';

Uint8List hex(String value) => Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);

String toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final deviceId = hex('0102030405060708090a0b0c0d0e0f10');
  const serverId = 'srv_test_server_id';
  final scalar = Uint8List.fromList(List<int>.filled(32, 0x0a));
  final serverShare =
      hex('cf7d76f2a0091c706bd51ed10439558590f3031f5a2fd262521314f5995e170f');
  final salt = Uint8List.fromList(List<int>.filled(16, 0x0c));

  group('Spake2Client shared vector', () {
    late Spake2Client client;
    late Spake2Result result;

    setUp(() async {
      client = await Spake2Client.start('123456', deviceId, serverId,
          clientScalar: scalar);
      result = await client.finish(serverShare, salt);
    });

    test('derives the password scalar and the client share', () {
      expect(toHex(client.passwordScalarBytes),
          'e4b7db0584fedda97976ce77dbb049a49abd89ebbcd04705cc40851e4fefe308');
      expect(toHex(client.publicShare),
          'c2619681afa765c1c73d952ec776d370ccbd7f3e5c64a78383cb459b95f10624');
    });

    test('derives the shared point and the transcript', () {
      expect(toHex(result.sharedPoint),
          '9f4bdc7c8bc6bda13ca065c6f37b095f9bc63ed718282363408739d93d11da55');
      expect(
        toHex(result.transcript),
        '10000000000000000102030405060708090a0b0c0d0e0f1012000000000000007372765f746573745f7365727665725f69642000000000000000c2619681afa765c1c73d952ec776d370ccbd7f3e5c64a78383cb459b95f106242000000000000000cf7d76f2a0091c706bd51ed10439558590f3031f5a2fd262521314f5995e170f20000000000000009f4bdc7c8bc6bda13ca065c6f37b095f9bc63ed718282363408739d93d11da552000000000000000e4b7db0584fedda97976ce77dbb049a49abd89ebbcd04705cc40851e4fefe308',
      );
    });

    test('derives the key schedule', () {
      expect(toHex(result.encryptionKey), '652524b5c2bb5f89a4d46732a6dec913');
      expect(
          toHex(result.confirmationSeed), 'c488b10a9bf8799fa0b8dded00af3584');
      expect(
          toHex(result.clientConfirmKey), '2092c35cbe36078612c86bd7a224f74a');
      expect(
          toHex(result.serverConfirmKey), 'a8edbd16895e7f91a4fa4eadf9fe8a09');
    });

    test('derives both confirmations and the wrap key', () {
      expect(toHex(result.clientConfirm),
          'a6e21298be44629b99c11163571612e0b6588586855d81b7d07363e6b86a092d');
      expect(toHex(result.serverConfirmExpected),
          'dadc8c80118a7ddcf2336b666596a6b604317a73cabfb8c7fd9ab1ed8308c2bd');
      expect(toHex(result.wrapKey),
          '7db26266ef6a13aad8b06502c8e21b8a13fe0c058cbec9dfcdd3f8115625268d');
    });

    test('opens a key sealed with the wrap key', () async {
      final deviceKey = randomBytes(32);
      final nonce = randomBytes(12);
      final aad = Spake2Client.sealedAad(deviceId, serverId);
      final box = await Chacha20.poly1305Aead().encrypt(
        deviceKey,
        secretKey: SecretKey(result.wrapKey),
        nonce: nonce,
        aad: aad,
      );
      final sealed = concatBytes([box.cipherText, box.mac.bytes]);

      final opened = await client.openSealed(nonce, sealed, aad);

      expect(opened, deviceKey);
    });

    test('rejects a sealed key with the wrong associated data', () async {
      final nonce = randomBytes(12);
      final box = await Chacha20.poly1305Aead().encrypt(
        randomBytes(32),
        secretKey: SecretKey(result.wrapKey),
        nonce: nonce,
        aad: Spake2Client.sealedAad(deviceId, serverId),
      );
      final sealed = concatBytes([box.cipherText, box.mac.bytes]);

      expect(
        client.openSealed(
            nonce, sealed, Spake2Client.sealedAad(deviceId, 'other')),
        throwsA(isA<Spake2Exception>()),
      );
    });
  });

  group('Spake2Client share validation', () {
    late Spake2Client client;

    setUp(() async {
      client = await Spake2Client.start('123456', deviceId, serverId,
          clientScalar: scalar);
    });

    test('rejects the identity point', () {
      final identity = Uint8List(32)..[0] = 1;

      expect(client.finish(identity, salt), throwsA(isA<Spake2Exception>()));
    });

    test('rejects a small order point', () {
      final order2 = Uint8List(32)
        ..[0] = 0xec
        ..setRange(1, 31, List<int>.filled(30, 0xff))
        ..[31] = 0x7f;

      expect(client.finish(order2, salt), throwsA(isA<Spake2Exception>()));
    });

    test('rejects bytes that are not a point', () {
      final garbage = Uint8List(32)..fillRange(0, 32, 0xff);

      expect(client.finish(garbage, salt), throwsA(isA<Spake2Exception>()));
    });
  });
}
