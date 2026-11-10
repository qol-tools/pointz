import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointz/services/command_service.dart';
import 'package:pointz/services/connection_status.dart';
import 'package:pointz/services/pairing/byte_codec.dart';
import 'package:pointz/services/pairing/command_envelope.dart';
import 'package:pointz/services/pairing/pairing_store.dart';

typedef Answer = Future<List<int>?> Function(Map<String, dynamic> envelope);

void main() {
  final pairing = PairedServer(
    serverId: 'server',
    deviceId: Uint8List.fromList(List<int>.generate(16, (i) => i + 1)),
    name: 'Phone',
    deviceKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
  );
  late RawDatagramSocket desktop;
  late CommandService service;
  Answer answer = (_) async => null;
  final received = <Map<String, dynamic>>[];

  Future<List<int>> pong(Map<String, dynamic> envelope) async => utf8.encode(
    jsonEncode(
      await CommandEnvelope.seal(
        key: pairing.deviceKey,
        deviceId: pairing.deviceId,
        command: {'type': 'Pong', 'nonce': envelope['nonce']},
        sentAtMs: 1,
        nonce: randomBytes(CommandEnvelope.nonceLength),
      ),
    ),
  );

  Future<List<int>> removed(Map<String, dynamic> envelope) async => utf8.encode(
    jsonEncode({
      'type': 'Rejected',
      'reason': 'unknown_device',
      'nonce': envelope['nonce'],
    }),
  );

  Future<void> until(ConnectionStatus wanted) async {
    final reached = Completer<void>();
    void check() {
      if (service.status.value == wanted && !reached.isCompleted) {
        reached.complete();
      }
    }

    service.status.addListener(check);
    check();
    await reached.future.timeout(const Duration(seconds: 5));
    service.status.removeListener(check);
  }

  CommandService start({bool reportsStatus = true}) => CommandService(
    InternetAddress.loopbackIPv4,
    pairing,
    reportsStatus: reportsStatus,
    port: desktop.port,
    pingInterval: const Duration(milliseconds: 40),
    replyTimeout: const Duration(milliseconds: 200),
  );

  setUp(() async {
    received.clear();
    answer = (_) async => null;
    desktop = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    desktop.listen((event) async {
      if (event != RawSocketEvent.read) return;
      final datagram = desktop.receive();
      if (datagram == null) return;
      final envelope =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      received.add(
        await CommandEnvelope.open(key: pairing.deviceKey, envelope: envelope),
      );
      final reply = await answer(envelope);
      if (reply != null) desktop.send(reply, datagram.address, datagram.port);
    });
  });

  tearDown(() {
    service.dispose();
    desktop.close();
  });

  test('it is connected only once the desktop answers a ping', () async {
    service = start();
    expect(service.status.value, ConnectionStatus.connecting);
    answer = pong;

    await service.connect();

    await until(ConnectionStatus.connected);
    expect(received.first, pingCommand);
  });

  test('a desktop that stops answering is reported and recovers', () async {
    service = start();
    answer = pong;
    await service.connect();
    await until(ConnectionStatus.connected);

    answer = (_) async => null;
    await until(ConnectionStatus.notResponding);

    answer = pong;
    await until(ConnectionStatus.connected);
  });

  test('a desktop that never answers is not shown as connected', () async {
    service = start();

    await service.connect();

    await until(ConnectionStatus.notResponding);
  });

  test('a phone the desktop removed learns it', () async {
    service = start();
    answer = pong;
    await service.connect();
    await until(ConnectionStatus.connected);

    answer = removed;

    await until(ConnectionStatus.removed);
  });

  test('an older desktop is never pinged', () async {
    service = start(reportsStatus: false);

    await service.connect();
    await service.mouseClick(1);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(service.status.value, ConnectionStatus.unconfirmed);
    expect(received, [
      {'type': 'MouseClick', 'button': 1},
    ]);
  });
}
