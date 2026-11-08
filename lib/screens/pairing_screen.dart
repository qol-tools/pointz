import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/discovery_service.dart';
import '../services/pairing/pair_messages.dart';
import '../services/pairing/pairing_service.dart';
import '../services/pairing/pairing_store.dart';
import 'control_screen.dart';

class PairingScreen extends StatefulWidget {
  static const int codeLength = 6;

  final DiscoveredServer server;
  final PairingService? pairingService;

  const PairingScreen({
    super.key,
    required this.server,
    this.pairingService,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _codeController = TextEditingController();
  late final PairingService _pairingService =
      widget.pairingService ?? PairingService(PairingStore());
  String _status = 'Enter the code shown on the desktop';
  bool _isPairing = false;

  bool get _codeComplete =>
      _codeController.text.length == PairingScreen.codeLength;

  Future<void> _pair() async {
    final serverId = widget.server.serverId;
    if (serverId == null) return;
    setState(() {
      _isPairing = true;
      _status = 'Pairing...';
    });
    try {
      final pairing = await _pairingService.pair(
        address: widget.server.address,
        serverId: serverId,
        pin: _codeController.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ControlScreen(
            serverAddress: widget.server.address,
            pairing: pairing,
          ),
        ),
      );
    } on PairingFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isPairing = false;
        _status = failure.message;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pair with ${widget.server.hostname}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _codeController,
              enabled: !_isPairing,
              keyboardType: TextInputType.number,
              maxLength: PairingScreen.codeLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Pairing code',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isPairing || !_codeComplete ? null : _pair,
              child: const Text('Pair'),
            ),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
