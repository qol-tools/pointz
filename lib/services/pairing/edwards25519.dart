import 'dart:typed_data';

import 'byte_codec.dart';

final BigInt _fieldPrime = (BigInt.one << 255) - BigInt.from(19);
final BigInt groupOrder = (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');
final BigInt cofactor = BigInt.from(8);
final BigInt _curveD =
    (BigInt.from(-121665) * _invert(BigInt.from(121666))) % _fieldPrime;
final BigInt _curveTwoD = (_curveD * BigInt.from(2)) % _fieldPrime;
final BigInt _sqrtMinusOne = BigInt.from(2)
    .modPow((_fieldPrime - BigInt.one) ~/ BigInt.from(4), _fieldPrime);

BigInt _invert(BigInt value) =>
    value.modPow(_fieldPrime - BigInt.from(2), _fieldPrime);

class EdPoint {
  final BigInt _x;
  final BigInt _y;
  final BigInt _z;
  final BigInt _t;

  EdPoint._(this._x, this._y, this._z, this._t);

  static final EdPoint identity =
      EdPoint._(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);

  static final EdPoint base =
      decode(Uint8List.fromList([0x58, ...List<int>.filled(31, 0x66)]))!;

  static EdPoint? decode(Uint8List bytes) {
    if (bytes.length != 32) return null;
    final signBit = (bytes[31] >> 7) & 1;
    final yBytes = Uint8List.fromList(bytes)..[31] &= 0x7f;
    final y = littleEndianToBigInt(yBytes);
    if (y >= _fieldPrime) return null;
    final ySquared = (y * y) % _fieldPrime;
    final numerator = (ySquared - BigInt.one) % _fieldPrime;
    final denominator = (_curveD * ySquared + BigInt.one) % _fieldPrime;
    final xSquared = (numerator * _invert(denominator)) % _fieldPrime;
    var x = xSquared.modPow(
        (_fieldPrime + BigInt.from(3)) ~/ BigInt.from(8), _fieldPrime);
    if ((x * x) % _fieldPrime != xSquared) {
      x = (x * _sqrtMinusOne) % _fieldPrime;
    }
    if ((x * x) % _fieldPrime != xSquared) return null;
    if (x == BigInt.zero && signBit == 1) return null;
    if (x.isOdd != (signBit == 1)) x = _fieldPrime - x;
    return EdPoint._(x, y, BigInt.one, (x * y) % _fieldPrime);
  }

  Uint8List encode() {
    final zInverse = _invert(_z);
    final x = (_x * zInverse) % _fieldPrime;
    final y = (_y * zInverse) % _fieldPrime;
    final out = bigIntToLittleEndian(y, 32);
    if (x.isOdd) out[31] |= 0x80;
    return out;
  }

  EdPoint operator +(EdPoint other) {
    final a = ((_y - _x) * (other._y - other._x)) % _fieldPrime;
    final b = ((_y + _x) * (other._y + other._x)) % _fieldPrime;
    final c = (_t * _curveTwoD * other._t) % _fieldPrime;
    final d = (_z * BigInt.from(2) * other._z) % _fieldPrime;
    final e = b - a;
    final f = d - c;
    final g = d + c;
    final h = b + a;
    return EdPoint._(
      (e * f) % _fieldPrime,
      (g * h) % _fieldPrime,
      (f * g) % _fieldPrime,
      (e * h) % _fieldPrime,
    );
  }

  EdPoint operator -() =>
      EdPoint._((-_x) % _fieldPrime, _y, _z, (-_t) % _fieldPrime);

  EdPoint subtract(EdPoint other) => this + (-other);

  EdPoint multiply(BigInt scalar) {
    var result = identity;
    var addend = this;
    for (var i = 0; i < scalar.bitLength; i++) {
      if ((scalar >> i).isOdd) result = result + addend;
      addend = addend + addend;
    }
    return result;
  }

  bool get isIdentity =>
      _x % _fieldPrime == BigInt.zero && (_y - _z) % _fieldPrime == BigInt.zero;

  bool get hasSmallOrder => multiply(cofactor).isIdentity;
}
