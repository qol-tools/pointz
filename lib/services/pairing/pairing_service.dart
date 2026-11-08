import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'byte_codec.dart';
import 'pair_messages.dart';
import 'pairing_store.dart';
import 'spake2_client.dart';

class PairingService {
  static const int pairingPort = 45454;
  static const Duration replyTimeout = Duration(seconds: 5);
  static const int maxNameLength = 64;

  final PairingStore _store;

  PairingService(this._store);

  Future<PairedServer> pair({
    required InternetAddress address,
    required String serverId,
    required String pin,
  }) async {
    final deviceId = await _store.deviceId();
    final name = _deviceName();
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final inbox = _Inbox(socket, address);
    try {
      final client = await Spake2Client.start(pin, deviceId, serverId);
      _send(
        socket,
        address,
        pairHelloMessage(
          deviceId: deviceId,
          name: name,
          publicShare: client.publicShare,
        ),
      );
      final offer = PairOffer.parse(await inbox.next('PairOffer'));
      if (offer.serverId != serverId) {
        throw const PairingFailure(
            'the desktop identity changed, search again');
      }
      final Spake2Result result;
      try {
        result = await client.finish(offer.serverShare, offer.salt);
      } on Spake2Exception {
        throw const PairingFailure('the desktop sent an invalid offer');
      }
      _send(
        socket,
        address,
        pairConfirmMessage(
          deviceId: deviceId,
          clientConfirm: result.clientConfirm,
        ),
      );
      final outcome = PairResult.parse(await inbox.next('PairResult'));
      if (!constantTimeEquals(
          outcome.serverConfirm, result.serverConfirmExpected)) {
        throw const PairingFailure('could not verify the desktop');
      }
      final Uint8List deviceKey;
      try {
        deviceKey = await client.openSealed(
          outcome.wrapNonce,
          outcome.sealed,
          Spake2Client.sealedAad(deviceId, serverId),
        );
      } on Spake2Exception {
        throw const PairingFailure('could not verify the desktop');
      }
      final pairing = PairedServer(
        serverId: serverId,
        deviceId: deviceId,
        name: name,
        deviceKey: deviceKey,
      );
      await _store.save(pairing);
      return pairing;
    } finally {
      socket.close();
    }
  }

  String _deviceName() {
    final hostname = Platform.localHostname;
    final name = hostname.isEmpty ? 'phone' : hostname;
    return name.length > maxNameLength
        ? name.substring(0, maxNameLength)
        : name;
  }

  void _send(
    RawDatagramSocket socket,
    InternetAddress address,
    Map<String, dynamic> message,
  ) {
    socket.send(utf8.encode(jsonEncode(message)), address, pairingPort);
  }
}

class _Inbox {
  final List<Map<String, dynamic>> _queue = [];
  Completer<void>? _arrival;

  _Inbox(RawDatagramSocket socket, InternetAddress expectedSender) {
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || datagram.address != expectedSender) return;
      try {
        final decoded = jsonDecode(utf8.decode(datagram.data));
        if (decoded is Map<String, dynamic>) {
          _queue.add(decoded);
          final waiting = _arrival;
          _arrival = null;
          waiting?.complete();
        }
      } on FormatException {
        return;
      }
    });
  }

  Future<Map<String, dynamic>> next(String expectedType) async {
    final deadline = DateTime.now().add(PairingService.replyTimeout);
    while (true) {
      while (_queue.isNotEmpty) {
        final message = _queue.removeAt(0);
        if (message['type'] == 'PairError') {
          throw PairingFailure(describePairError(message));
        }
        if (message['type'] == expectedType) return message;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const PairingFailure('no answer from the desktop');
      }
      final arrival = Completer<void>();
      _arrival = arrival;
      await arrival.future.timeout(remaining, onTimeout: () {});
      _arrival = null;
    }
  }
}
