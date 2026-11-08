import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

String encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List? tryDecodeBase64Url(Object? value, {int? expectedLength}) {
  if (value is! String) return null;
  try {
    final bytes =
        Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
    if (expectedLength != null && bytes.length != expectedLength) return null;
    return bytes;
  } on FormatException {
    return null;
  }
}

Uint8List randomBytes(int length, [Random? random]) {
  final source = random ?? Random.secure();
  return Uint8List.fromList(
      List<int>.generate(length, (_) => source.nextInt(256)));
}

Uint8List concatBytes(Iterable<List<int>> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.toBytes();
}

Uint8List lengthPrefixed(List<int> bytes) {
  final prefix = bigIntToLittleEndian(BigInt.from(bytes.length), 8);
  return concatBytes([prefix, bytes]);
}

BigInt littleEndianToBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

Uint8List bigIntToLittleEndian(BigInt value, int length) {
  final out = Uint8List(length);
  var rest = value;
  final mask = BigInt.from(0xff);
  for (var i = 0; i < length; i++) {
    out[i] = (rest & mask).toInt();
    rest = rest >> 8;
  }
  return out;
}

Uint8List unixMillisBigEndian(int millis) {
  final out = Uint8List(8);
  var rest = millis;
  for (var i = 7; i >= 0; i--) {
    out[i] = rest % 256;
    rest = rest ~/ 256;
  }
  return out;
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Uint8List utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));
