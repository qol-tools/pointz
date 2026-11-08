import 'package:flutter/material.dart';
import '../services/discovery_service.dart';
import '../services/pairing/pairing_store.dart';
import 'control_screen.dart';
import 'pairing_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  ServerDiscovery? _discovery;
  final Set<DiscoveredServer> _discoveredServers = {};
  final PairingStore _pairingStore = PairingStore();
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _isDiscovering = true;
      _discoveredServers.clear();
    });

    _discovery = await ServerDiscovery.start();
    _discovery!.discoveredServers.listen((server) {
      if (mounted) {
        setState(() {
          _discoveredServers.remove(server);
          _discoveredServers.add(server);
          _isDiscovering = false;
        });
      }
    });

    await _discovery!.discover();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    });
  }

  String? _incompatibilityMessage(DiscoveredServer server) {
    switch (server.compatibility) {
      case ServerCompatibility.ready:
        return null;
      case ServerCompatibility.needsCurrentApp:
        return 'This app is older than the desktop, update it';
      case ServerCompatibility.needsCurrentDesktop:
        return 'Older PointZ on the desktop, update qol there';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connectToServer(DiscoveredServer server) async {
    final incompatibility = _incompatibilityMessage(server);
    if (incompatibility != null) {
      _showMessage(incompatibility);
      return;
    }
    final pairing = await _pairingStore.find(server.serverId!);
    if (!mounted) return;
    if (pairing == null) {
      _openPairing(server);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ControlScreen(
          serverAddress: server.address,
          pairing: pairing,
        ),
      ),
    );
  }

  void _openPairing(DiscoveredServer server) {
    if (server.compatibility != ServerCompatibility.ready) return;
    if (!server.pairingOpen) {
      _showMessage('Open pairing on the desktop first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PairingScreen(server: server),
      ),
    );
  }

  String _serverSubtitle(DiscoveredServer server) {
    final incompatibility = _incompatibilityMessage(server);
    if (incompatibility != null) {
      return '${server.address.address} - $incompatibility';
    }
    if (server.pairingOpen) return '${server.address.address} - pairing open';
    return server.address.address;
  }

  @override
  void dispose() {
    _discovery?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PointZ'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_isDiscovering)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              )
            else if (_discoveredServers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Found ${_discoveredServers.length} server${_discoveredServers.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _discoveredServers.length,
                  itemBuilder: (context, index) {
                    final server = _discoveredServers.elementAt(index);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text(server.hostname),
                        subtitle: Text(_serverSubtitle(server)),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () => _connectToServer(server),
                        onLongPress: () => _openPairing(server),
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton(
                onPressed: _startDiscovery,
                child: const Text('Search Again'),
              ),
            ] else ...[
              const Spacer(),
              const Icon(Icons.search_off, size: 64),
              const SizedBox(height: 16),
              const Text('No server found'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startDiscovery,
                child: const Text('Search Again'),
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }
}
