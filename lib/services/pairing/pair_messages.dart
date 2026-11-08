import 'dart:typed_data';

import 'byte_codec.dart';

class PairingFailure implements Exception {
  final String message;

  const PairingFailure(this.message);

  @override
  String toString() => message;
}

const int pairingProtocol = 2;

String describePairError(Map<String, dynamic> json) {
  final attemptsLeft = json['attempts_left'];
  switch (json['reason']) {
    case 'bad_pin':
      if (attemptsLeft is! int) return 'wrong code';
      if (attemptsLeft <= 0) return 'wrong code, pairing closed';
      return 'wrong code, $attemptsLeft ${attemptsLeft == 1 ? 'attempt' : 'attempts'} left';
    case 'closed':
      return 'pairing closed';
    case 'protocol':
      return 'update the app';
    case 'busy':
      return 'another phone is pairing, try again shortly';
    case 'no_session':
      return 'pairing timed out, try again';
    case 'unavailable':
      return 'pairing is unavailable on the desktop';
    case 'bad_request':
      return 'the desktop rejected the request, try again';
    default:
      return 'pairing failed';
  }
}

Map<String, dynamic> pairHelloMessage({
  required Uint8List deviceId,
  required String name,
  required Uint8List publicShare,
}) =>
    {
      'type': 'PairHello',
      'protocol': pairingProtocol,
      'device_id': encodeBase64Url(deviceId),
      'name': name,
      'pa': encodeBase64Url(publicShare),
    };

Map<String, dynamic> pairConfirmMessage({
  required Uint8List deviceId,
  required Uint8List clientConfirm,
}) =>
    {
      'type': 'PairConfirm',
      'protocol': pairingProtocol,
      'device_id': encodeBase64Url(deviceId),
      'client_confirm': encodeBase64Url(clientConfirm),
    };

class PairOffer {
  final String serverId;
  final Uint8List serverShare;
  final Uint8List salt;

  const PairOffer({
    required this.serverId,
    required this.serverShare,
    required this.salt,
  });

  static PairOffer parse(Map<String, dynamic> json) {
    final serverId = json['server_id'];
    final serverShare = tryDecodeBase64Url(json['pb'], expectedLength: 32);
    final salt = tryDecodeBase64Url(json['salt'], expectedLength: 16);
    if (serverId is! String || serverShare == null || salt == null) {
      throw const PairingFailure('the desktop sent an invalid offer');
    }
    return PairOffer(serverId: serverId, serverShare: serverShare, salt: salt);
  }
}

class PairResult {
  final Uint8List serverConfirm;
  final Uint8List wrapNonce;
  final Uint8List sealed;

  const PairResult({
    required this.serverConfirm,
    required this.wrapNonce,
    required this.sealed,
  });

  static PairResult parse(Map<String, dynamic> json) {
    final serverConfirm =
        tryDecodeBase64Url(json['server_confirm'], expectedLength: 32);
    final wrapNonce =
        tryDecodeBase64Url(json['wrap_nonce'], expectedLength: 12);
    final sealed = tryDecodeBase64Url(json['sealed'], expectedLength: 48);
    if (serverConfirm == null || wrapNonce == null || sealed == null) {
      throw const PairingFailure('the desktop sent an invalid result');
    }
    return PairResult(
      serverConfirm: serverConfirm,
      wrapNonce: wrapNonce,
      sealed: sealed,
    );
  }
}
