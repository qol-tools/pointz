import 'dart:convert';
import 'dart:typed_data';

import 'pairing/byte_codec.dart';
import 'pairing/command_envelope.dart';

enum ConnectionStatus {
  connecting,
  connected,
  notResponding,
  removed,
  clockMismatch,
  unconfirmed,
}

const Map<String, dynamic> pingCommand = {'type': 'Ping'};

Future<ConnectionStatus?> readServerReply({
  required Uint8List data,
  required Uint8List key,
  required Uint8List pingNonce,
}) async {
  try {
    final json = jsonDecode(utf8.decode(data));
    if (json is! Map<String, dynamic>) return null;
    if (json['type'] == 'Rejected') {
      final removed = json['reason'] == 'unknown_device';
      if (!removed || !_answers(json, pingNonce)) return null;
      return ConnectionStatus.removed;
    }
    final reply = await CommandEnvelope.open(key: key, envelope: json);
    if (!_answers(reply, pingNonce)) return null;
    return switch ((reply['type'], reply['reason'])) {
      ('Pong', _) => ConnectionStatus.connected,
      ('Rejected', 'clock') => ConnectionStatus.clockMismatch,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

bool _answers(Map<String, dynamic> reply, Uint8List pingNonce) {
  final nonce = tryDecodeBase64Url(
    reply['nonce'],
    expectedLength: CommandEnvelope.nonceLength,
  );
  return nonce != null && constantTimeEquals(nonce, pingNonce);
}
