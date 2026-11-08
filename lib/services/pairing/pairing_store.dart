import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'byte_codec.dart';

class PairedServer {
  final String serverId;
  final Uint8List deviceId;
  final String name;
  final Uint8List deviceKey;

  const PairedServer({
    required this.serverId,
    required this.deviceId,
    required this.name,
    required this.deviceKey,
  });

  Map<String, dynamic> toJson() => {
        'server_id': serverId,
        'device_id': encodeBase64Url(deviceId),
        'name': name,
        'device_key': encodeBase64Url(deviceKey),
      };

  static PairedServer? fromJson(Object? json) {
    if (json is! Map) return null;
    final serverId = json['server_id'];
    final name = json['name'];
    final deviceId = tryDecodeBase64Url(json['device_id'], expectedLength: 16);
    final deviceKey =
        tryDecodeBase64Url(json['device_key'], expectedLength: 32);
    if (serverId is! String || name is! String) return null;
    if (deviceId == null || deviceKey == null) return null;
    return PairedServer(
      serverId: serverId,
      deviceId: deviceId,
      name: name,
      deviceKey: deviceKey,
    );
  }
}

class PairingStore {
  static const String _deviceIdKey = 'pointz.device_id';
  static const String _pairingsKey = 'pointz.pairings';

  final FlutterSecureStorage _storage;

  PairingStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<Uint8List> deviceId() async {
    final stored = tryDecodeBase64Url(
      await _storage.read(key: _deviceIdKey),
      expectedLength: 16,
    );
    if (stored != null) return stored;
    final created = randomBytes(16);
    await _storage.write(key: _deviceIdKey, value: encodeBase64Url(created));
    return created;
  }

  Future<PairedServer?> find(String serverId) async =>
      (await _readAll())[serverId];

  Future<void> save(PairedServer pairing) async {
    final all = await _readAll();
    all[pairing.serverId] = pairing;
    await _storage.write(
      key: _pairingsKey,
      value: jsonEncode([for (final entry in all.values) entry.toJson()]),
    );
  }

  Future<Map<String, PairedServer>> _readAll() async {
    final raw = await _storage.read(key: _pairingsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return {
        for (final item in decoded)
          if (PairedServer.fromJson(item) case final pairing?)
            pairing.serverId: pairing,
      };
    } on FormatException {
      return {};
    }
  }
}
