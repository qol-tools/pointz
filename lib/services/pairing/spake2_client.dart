import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'byte_codec.dart';
import 'edwards25519.dart';

class Spake2Exception implements Exception {
  final String message;

  const Spake2Exception(this.message);

  @override
  String toString() => message;
}

class Spake2Result {
  final Uint8List sharedPoint;
  final Uint8List transcript;
  final Uint8List encryptionKey;
  final Uint8List confirmationSeed;
  final Uint8List clientConfirmKey;
  final Uint8List serverConfirmKey;
  final Uint8List clientConfirm;
  final Uint8List serverConfirmExpected;
  final Uint8List wrapKey;

  const Spake2Result({
    required this.sharedPoint,
    required this.transcript,
    required this.encryptionKey,
    required this.confirmationSeed,
    required this.clientConfirmKey,
    required this.serverConfirmKey,
    required this.clientConfirm,
    required this.serverConfirmExpected,
    required this.wrapKey,
  });
}

class Spake2Client {
  static const String _passwordLabel = 'pointz-spake2-v2';
  static const String _confirmationInfo = 'ConfirmationKeys';
  static const String _wrapInfo = 'pointz-pair-wrap-v2';
  static const int sealedLength = 48;

  static final EdPoint _pointM = EdPoint.decode(_hexBytes(
      'd048032c6ea0b6d697ddc2e86bda85a33adac920f1bf18e1b0c6d166a5cecdaf'))!;
  static final EdPoint _pointN = EdPoint.decode(_hexBytes(
      'd3bfb518f44f3430f29d0c92af503865a1ed3281dc69b35dd868ba85f886c4ab'))!;

  final Uint8List deviceId;
  final Uint8List serverIdBytes;
  final BigInt _clientScalar;
  final BigInt _passwordScalar;
  final Uint8List passwordScalarBytes;
  final Uint8List publicShare;
  Uint8List? _wrapKey;

  Spake2Client._(
    this.deviceId,
    this.serverIdBytes,
    this._clientScalar,
    this._passwordScalar,
    this.passwordScalarBytes,
    this.publicShare,
  );

  static Future<Spake2Client> start(
    String pin,
    Uint8List deviceId,
    String serverId, {
    Uint8List? clientScalar,
  }) async {
    final serverIdBytes = utf8Bytes(serverId);
    final pinBytes = utf8Bytes(pin);
    final digest = await Sha512().hash(concatBytes([
      utf8Bytes(_passwordLabel),
      lengthPrefixed(pinBytes),
      lengthPrefixed(deviceId),
      lengthPrefixed(serverIdBytes),
    ]));
    final password = littleEndianToBigInt(digest.bytes) % groupOrder;
    final scalar = clientScalar != null
        ? littleEndianToBigInt(clientScalar) % groupOrder
        : littleEndianToBigInt(randomBytes(64)) % groupOrder;
    if (scalar == BigInt.zero) {
      throw const Spake2Exception('weak random scalar');
    }
    final share = EdPoint.base.multiply(scalar) + _pointM.multiply(password);
    return Spake2Client._(
      Uint8List.fromList(deviceId),
      serverIdBytes,
      scalar,
      password,
      bigIntToLittleEndian(password, 32),
      share.encode(),
    );
  }

  Future<Spake2Result> finish(Uint8List serverShare, Uint8List salt) async {
    final peer = EdPoint.decode(serverShare);
    if (peer == null || peer.isIdentity || peer.hasSmallOrder) {
      throw const Spake2Exception('invalid desktop share');
    }
    final unmasked = peer.subtract(_pointN.multiply(_passwordScalar));
    final shared = unmasked.multiply(_clientScalar * cofactor);
    if (shared.isIdentity) {
      throw const Spake2Exception('invalid shared point');
    }
    final sharedBytes = shared.encode();
    final transcript = concatBytes([
      lengthPrefixed(deviceId),
      lengthPrefixed(serverIdBytes),
      lengthPrefixed(publicShare),
      lengthPrefixed(serverShare),
      lengthPrefixed(sharedBytes),
      lengthPrefixed(passwordScalarBytes),
    ]);
    final transcriptHash = (await Sha256().hash(transcript)).bytes;
    final encryptionKey = Uint8List.fromList(transcriptHash.sublist(0, 16));
    final confirmationSeed = Uint8List.fromList(transcriptHash.sublist(16, 32));
    final confirmationKeys =
        await _hkdf(confirmationSeed, const [], utf8Bytes(_confirmationInfo));
    final clientConfirmKey =
        Uint8List.fromList(confirmationKeys.sublist(0, 16));
    final serverConfirmKey =
        Uint8List.fromList(confirmationKeys.sublist(16, 32));
    final wrapKey = await _hkdf(encryptionKey, salt, utf8Bytes(_wrapInfo));
    _wrapKey = wrapKey;
    return Spake2Result(
      sharedPoint: sharedBytes,
      transcript: transcript,
      encryptionKey: encryptionKey,
      confirmationSeed: confirmationSeed,
      clientConfirmKey: clientConfirmKey,
      serverConfirmKey: serverConfirmKey,
      clientConfirm: await _hmac(clientConfirmKey, transcript),
      serverConfirmExpected: await _hmac(serverConfirmKey, transcript),
      wrapKey: wrapKey,
    );
  }

  static Uint8List sealedAad(Uint8List deviceId, String serverId) =>
      concatBytes([deviceId, utf8Bytes(serverId)]);

  Future<Uint8List> openSealed(
    Uint8List nonce,
    Uint8List sealed,
    Uint8List aad,
  ) async {
    final wrapKey = _wrapKey;
    if (wrapKey == null) {
      throw const Spake2Exception('pairing not finished');
    }
    if (sealed.length != sealedLength) {
      throw const Spake2Exception('invalid sealed key');
    }
    final box = SecretBox(
      sealed.sublist(0, sealedLength - 16),
      nonce: nonce,
      mac: Mac(sealed.sublist(sealedLength - 16)),
    );
    try {
      final clear = await Chacha20.poly1305Aead()
          .decrypt(box, secretKey: SecretKey(wrapKey), aad: aad);
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const Spake2Exception('sealed key rejected');
    }
  }

  static Future<Uint8List> _hkdf(
    List<int> inputKey,
    List<int> salt,
    List<int> info,
  ) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(inputKey),
      nonce: salt,
      info: info,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<Uint8List> _hmac(List<int> key, List<int> data) async {
    final mac =
        await Hmac.sha256().calculateMac(data, secretKey: SecretKey(key));
    return Uint8List.fromList(mac.bytes);
  }

  static Uint8List _hexBytes(String hex) => Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
}
