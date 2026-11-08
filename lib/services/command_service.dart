import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pairing/byte_codec.dart';
import 'pairing/command_envelope.dart';
import 'pairing/pairing_store.dart';

class CommandService {
  static const int commandPort = 45455;

  final InternetAddress _serverAddress;
  final PairedServer _pairing;
  RawDatagramSocket? _socket;

  CommandService(this._serverAddress, this._pairing);

  Future<void> connect() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
  }

  Future<void> sendCommand(Map<String, dynamic> command) async {
    if (_socket == null) {
      await connect();
    }

    final envelope = await CommandEnvelope.seal(
      key: _pairing.deviceKey,
      deviceId: _pairing.deviceId,
      command: command,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
      nonce: randomBytes(CommandEnvelope.nonceLength),
    );
    final data = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    _socket?.send(data, _serverAddress, commandPort);
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
    _socket?.close();
  }
}
