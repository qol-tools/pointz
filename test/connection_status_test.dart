import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointz/services/connection_status.dart';
import 'package:pointz/services/pairing/byte_codec.dart';
import 'package:pointz/services/pairing/command_envelope.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final otherKey = Uint8List.fromList(List<int>.filled(32, 9));
  final deviceId = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
  final pingNonce = Uint8List.fromList(List<int>.filled(12, 5));
  final otherNonce = Uint8List.fromList(List<int>.filled(12, 6));

  Future<Uint8List> sealed(
    Map<String, dynamic> reply, {
    Uint8List? withKey,
  }) async {
    final envelope = await CommandEnvelope.seal(
      key: withKey ?? key,
      deviceId: deviceId,
      command: reply,
      sentAtMs: 1700000000123,
      nonce: Uint8List.fromList(List<int>.filled(12, 7)),
    );
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Uint8List rejected(String reason, Uint8List nonce) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'type': 'Rejected',
        'reason': reason,
        'nonce': encodeBase64Url(nonce),
      }),
    ),
  );

  Future<ConnectionStatus?> read(Uint8List data) =>
      readServerReply(data: data, key: key, pingNonce: pingNonce);

  test('a sealed pong for the open ping means connected', () async {
    final pong = await sealed({
      'type': 'Pong',
      'nonce': encodeBase64Url(pingNonce),
    });

    expect(await read(pong), ConnectionStatus.connected);
  });

  test('a pong for another ping, key or type is ignored', () async {
    final stale = await sealed({
      'type': 'Pong',
      'nonce': encodeBase64Url(otherNonce),
    });
    final forged = await sealed({
      'type': 'Pong',
      'nonce': encodeBase64Url(pingNonce),
    }, withKey: otherKey);
    final reflected = await sealed(pingCommand);

    expect(await read(stale), null);
    expect(await read(forged), null);
    expect(await read(reflected), null);
  });

  test('a clear rejection of the open ping means this phone was removed',
      () async {
    expect(await read(rejected('unknown_device', pingNonce)),
        ConnectionStatus.removed);
    expect(await read(rejected('unknown_device', otherNonce)), null);
    expect(await read(rejected('later', pingNonce)), null);
  });

  test('a clock rejection counts only when sealed with the device key',
      () async {
    final clock = {
      'type': 'Rejected',
      'reason': 'clock',
      'nonce': encodeBase64Url(pingNonce),
    };

    expect(await read(await sealed(clock)), ConnectionStatus.clockMismatch);
    expect(await read(await sealed(clock, withKey: otherKey)), null);
    expect(await read(rejected('clock', pingNonce)), null);
    expect(
        await read(await sealed({
          'type': 'Rejected',
          'reason': 'unknown_device',
          'nonce': encodeBase64Url(pingNonce),
        })),
        null);
  });

  test('anything that is not a reply is ignored', () async {
    expect(await read(Uint8List.fromList(utf8.encode('POINTZ_SERVER'))), null);
    expect(await read(Uint8List.fromList(utf8.encode('[1]'))), null);
    expect(await read(Uint8List.fromList(utf8.encode('{"version":3}'))), null);
    expect(await read(Uint8List.fromList([0xff, 0xfe])), null);
  });
}
