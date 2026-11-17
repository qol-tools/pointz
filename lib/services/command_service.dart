import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'connection_status.dart';
import 'pairing/byte_codec.dart';
import 'pairing/command_envelope.dart';
import 'pairing/pairing_store.dart';

class CommandService {
  static const int commandPort = 45455;
  static const Duration defaultPingInterval = Duration(seconds: 2);
  static const Duration defaultReplyTimeout = Duration(seconds: 5);

  final InternetAddress _serverAddress;
  final PairedServer _pairing;
  final bool _reportsStatus;
  final int _port;
  final Duration _pingInterval;
  final Duration _replyTimeout;
  final ValueNotifier<ConnectionStatus> status;
  final Stopwatch _silence = Stopwatch();
  RawDatagramSocket? _socket;
  Timer? _pingTimer;
  Uint8List? _pingNonce;
  bool _disposed = false;

  CommandService(
    this._serverAddress,
    this._pairing, {
    bool reportsStatus = true,
    int port = commandPort,
    Duration pingInterval = defaultPingInterval,
    Duration replyTimeout = defaultReplyTimeout,
  }) : _reportsStatus = reportsStatus,
       _port = port,
       _pingInterval = pingInterval,
       _replyTimeout = replyTimeout,
       status = ValueNotifier(
         reportsStatus
             ? ConnectionStatus.connecting
             : ConnectionStatus.unconfirmed,
       );

  Future<void> connect() async {
    if (_socket != null || _disposed) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    if (_disposed) {
      socket.close();
      return;
    }
    socket.broadcastEnabled = true;
    _socket = socket;
    if (!_reportsStatus) return;
    socket.listen(_handleSocketEvent);
    _silence.start();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _ping());
    await _ping();
  }

  Future<void> sendCommand(Map<String, dynamic> command) async {
    if (_socket == null) {
      await connect();
    }
    await _send(command, randomBytes(CommandEnvelope.nonceLength));
  }

  Future<void> _send(Map<String, dynamic> command, Uint8List nonce) async {
    final envelope = await CommandEnvelope.seal(
      key: _pairing.deviceKey,
      deviceId: _pairing.deviceId,
      command: command,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
      nonce: nonce,
    );
    final data = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    try {
      _socket?.send(data, _serverAddress, _port);
    } on SocketException {
      return;
    }
  }

  Future<void> _ping() async {
    if (_disposed) return;
    if (_silence.elapsed > _replyTimeout) {
      status.value = ConnectionStatus.notResponding;
    }
    final nonce = randomBytes(CommandEnvelope.nonceLength);
    _pingNonce = nonce;
    await _send(pingCommand, nonce);
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    if (datagram.address != _serverAddress || datagram.port != _port) return;
    _readReply(datagram.data);
  }

  Future<void> _readReply(Uint8List data) async {
    final pingNonce = _pingNonce;
    if (pingNonce == null) return;
    final answer = await readServerReply(
      data: data,
      key: _pairing.deviceKey,
      pingNonce: pingNonce,
    );
    if (answer == null || _disposed) return;
    _silence.reset();
    status.value = answer;
  }

  Future<void> mouseMove(double x, double y) async {
    await sendCommand({
      'type': 'MouseMove',
      'x': x,
      'y': y,
    });
  }

  Future<void> mouseClick(int button) async {
    await sendCommand({
      'type': 'MouseClick',
      'button': button,
    });
  }

  Future<void> mouseDown(int button) async {
    await sendCommand({
      'type': 'MouseDown',
      'button': button,
    });
  }

  Future<void> mouseUp(int button) async {
    await sendCommand({
      'type': 'MouseUp',
      'button': button,
    });
  }

  Future<void> mouseScroll(double deltaX, double deltaY) async {
    await sendCommand({
      'type': 'MouseScroll',
      'delta_x': deltaX,
      'delta_y': deltaY,
    });
  }

  Future<void> keyPress(String key,
      {bool ctrl = false,
      bool alt = false,
      bool shift = false,
      bool meta = false}) async {
    await sendCommand({
      'type': 'KeyPress',
      'key': key,
      'modifiers': {
        'ctrl': ctrl,
        'alt': alt,
        'shift': shift,
        'meta': meta,
      },
    });
  }

  Future<void> keyRelease(String key,
      {bool ctrl = false,
      bool alt = false,
      bool shift = false,
      bool meta = false}) async {
    await sendCommand({
      'type': 'KeyRelease',
      'key': key,
      'modifiers': {
        'ctrl': ctrl,
        'alt': alt,
        'shift': shift,
        'meta': meta,
      },
    });
  }

  Future<void> modifierPress(String modifier) async {
    await sendCommand({
      'type': 'ModifierPress',
      'modifier': modifier,
    });
  }

  Future<void> modifierRelease(String modifier) async {
    await sendCommand({
      'type': 'ModifierRelease',
      'modifier': modifier,
    });
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _socket?.close();
    status.dispose();
  }
}
