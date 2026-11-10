import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointz/services/discovery_service.dart';
import 'package:pointz/services/pairing/pair_messages.dart';

void main() {
  final address = InternetAddress('192.168.1.5');

  group('DiscoveredServer.tryParse', () {
    test('reads the current reply', () {
      final server = DiscoveredServer.tryParse(
        jsonEncode({
          'hostname': 'desk',
          'server_id': 'srv_1',
          'authentication': 'pair-spake2-v2',
          'command': 'sealed-v3',
          'status': 'ping-v1',
          'pairing_open': true,
        }),
        address,
      )!;

      expect(server.hostname, 'desk');
      expect(server.serverId, 'srv_1');
      expect(server.pairingOpen, true);
      expect(server.reportsStatus, true);
      expect(server.compatibility, ServerCompatibility.ready);
    });

    test('a desktop without the status tag stays usable but unconfirmed', () {
      final server = DiscoveredServer.tryParse(
        jsonEncode({
          'hostname': 'desk',
          'server_id': 'srv_1',
          'authentication': 'pair-spake2-v2',
          'command': 'sealed-v3',
        }),
        address,
      )!;

      expect(server.reportsStatus, false);
      expect(server.compatibility, ServerCompatibility.ready);
    });

    test('reads an old reply as needing the current desktop', () {
      final server =
          DiscoveredServer.tryParse(jsonEncode({'hostname': 'old'}), address)!;

      expect(server.hostname, 'old');
      expect(server.serverId, null);
      expect(server.pairingOpen, false);
      expect(server.compatibility, ServerCompatibility.needsCurrentDesktop);
    });

    test('reads a reply with an unknown scheme as needing the current app', () {
      final server = DiscoveredServer.tryParse(
        jsonEncode({
          'hostname': 'new',
          'server_id': 'srv_2',
          'authentication': 'pair-future-v9',
          'command': 'sealed-v3',
        }),
        address,
      )!;

      expect(server.compatibility, ServerCompatibility.needsCurrentApp);
    });

    test('tolerates wrongly typed fields', () {
      final server = DiscoveredServer.tryParse(
        jsonEncode({'hostname': 4, 'server_id': [], 'pairing_open': 'yes'}),
        address,
      )!;

      expect(server.hostname, ServerDiscovery.unknownHostname);
      expect(server.serverId, null);
      expect(server.pairingOpen, false);
    });

    test('returns null for text that is not JSON', () {
      expect(DiscoveredServer.tryParse('POINTZ_SERVER', address), null);
    });
  });

  group('describePairError', () {
    test('renders a wrong code with attempts left', () {
      expect(
        describePairError({'reason': 'bad_pin', 'attempts_left': 2}),
        'wrong code, 2 attempts left',
      );
      expect(
        describePairError({'reason': 'bad_pin', 'attempts_left': 1}),
        'wrong code, 1 attempt left',
      );
    });

    test('renders a wrong code that closed the window', () {
      expect(
        describePairError({'reason': 'bad_pin', 'attempts_left': 0}),
        'wrong code, pairing closed',
      );
    });

    test('renders the other reasons', () {
      expect(describePairError({'reason': 'closed'}), 'pairing closed');
      expect(
        describePairError({'reason': 'protocol', 'expected': 2}),
        'update the app',
      );
      expect(describePairError({'reason': 'surprise'}), 'pairing failed');
    });
  });
}
