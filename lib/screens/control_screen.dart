import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/command_service.dart';
import '../services/connection_status.dart';
import '../services/discovery_service.dart';
import '../services/settings_service.dart';
import '../services/pairing/pairing_store.dart';
import '../features/gesture/gesture_handler.dart';
import '../features/gesture/gesture_detector.dart';
import '../features/gesture/config/gesture_config.dart';
import '../features/mouse_control/implementations/command_service_executor.dart';
import '../features/keyboard/keyboard_handler.dart';
import '../features/keyboard/implementations/command_service_keyboard_executor.dart';
import 'pairing_screen.dart';
import 'settings_screen.dart';

class ControlScreen extends StatefulWidget {
  final DiscoveredServer server;
  final PairedServer pairing;

  const ControlScreen({
    super.key,
    required this.server,
    required this.pairing,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late final CommandService _commandService = CommandService(
    widget.server.address,
    widget.pairing,
    reportsStatus: widget.server.reportsStatus,
  );
  late GestureHandler _gestureHandler;
  late FlutterGestureConverter _gestureConverter;
  late KeyboardHandler _keyboardHandler;
  late AppSettings _settings;
  late GestureConfig _gestureConfig;
  final FocusNode _physicalKeyboardFocusNode = FocusNode();
  final FocusNode _textFieldFocusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();
  String _previousText = '';
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    _settings = AppSettings();
    await _settings.load();
    _gestureConfig = GestureConfig(_settings);
    _initializeHandlers();
    _connect();
  }

  void _initializeHandlers() {
    final executor = CommandServiceExecutor(_commandService);
    final keyboardExecutor = CommandServiceKeyboardExecutor(_commandService);
    _gestureHandler = GestureHandler(executor, _gestureConfig);
    _gestureConverter = FlutterGestureConverter();
    _keyboardHandler = KeyboardHandler(keyboardExecutor);
  }

  Future<void> _connect() async {
    await _commandService.connect();
    if (!mounted) return;
    setState(() {
      _isConnected = true;
    });
  }

  void _pairAgain() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PairingScreen(server: widget.server),
      ),
    );
  }

  Widget _buildStatus(BuildContext context, ConnectionStatus status) {
    final (icon, color, label) = switch (status) {
      ConnectionStatus.connecting => (Icons.sync, Colors.grey, 'Connecting...'),
      ConnectionStatus.connected => (
        Icons.check_circle,
        Colors.green,
        'Connected',
      ),
      ConnectionStatus.notResponding => (
        Icons.error,
        Colors.red,
        'Desktop not responding',
      ),
      ConnectionStatus.removed => (
        Icons.link_off,
        Colors.red,
        'This phone was removed from PointZerver',
      ),
      ConnectionStatus.clockMismatch => (
        Icons.schedule,
        Colors.orange,
        'Phone and desktop clocks differ by over 30 seconds',
      ),
      ConnectionStatus.unconfirmed => (
        Icons.help,
        Colors.grey,
        'Sending. Update PointZerver to see the connection state',
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: color),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (status == ConnectionStatus.removed) ...[
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _pairAgain,
            child: const Text('Pair again'),
          ),
        ],
      ],
    );
  }

  Future<void> _onScaleStart(ScaleStartDetails details) async {
    if (!_isConnected) return;
    final event = _gestureConverter.onScaleStart(details);
    if (event != null) {
      await _gestureHandler.handleEvent(event);
    }
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    if (!_isConnected) return;
    final event = _gestureConverter.onScaleUpdate(details);
    if (event != null) {
      await _gestureHandler.handleEvent(event);
    }
  }

  Future<void> _onScaleEnd(ScaleEndDetails details) async {
    if (!_isConnected) return;
    final event = _gestureConverter.onScaleEnd(details);
    await _gestureHandler.handleEvent(event);
  }

  bool _isModifierPressed(LogicalKeyboardKey key) {
    return HardwareKeyboard.instance.logicalKeysPressed.contains(key);
  }

  Future<void> _handleKeyEvent(KeyEvent event) async {
    if (!_isConnected) return;

    final ctrl = _isModifierPressed(LogicalKeyboardKey.controlLeft) ||
        _isModifierPressed(LogicalKeyboardKey.controlRight);
    final alt = _isModifierPressed(LogicalKeyboardKey.altLeft) ||
        _isModifierPressed(LogicalKeyboardKey.altRight);
    final shift = _isModifierPressed(LogicalKeyboardKey.shiftLeft) ||
        _isModifierPressed(LogicalKeyboardKey.shiftRight);
    final meta = _isModifierPressed(LogicalKeyboardKey.metaLeft) ||
        _isModifierPressed(LogicalKeyboardKey.metaRight);

    if (event is KeyDownEvent) {
      final key = _keyEventToString(event);
      if (key != null) {
        await _keyboardHandler.handleKeyPress(
          key,
          ctrl: ctrl,
          alt: alt,
          shift: shift,
          meta: meta,
        );
      }

      // Handle modifier keys themselves
      if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight) {
        await _keyboardHandler.handleModifierPress('ctrl');
      } else if (event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight) {
        await _keyboardHandler.handleModifierPress('alt');
      } else if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
          event.logicalKey == LogicalKeyboardKey.shiftRight) {
        await _keyboardHandler.handleModifierPress('shift');
      } else if (event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight) {
        await _keyboardHandler.handleModifierPress('meta');
      }
    } else if (event is KeyUpEvent) {
      final key = _keyEventToString(event);
      if (key != null) {
        await _keyboardHandler.handleKeyRelease(
          key,
          ctrl: ctrl,
          alt: alt,
          shift: shift,
          meta: meta,
        );
      }

      // Handle modifier keys themselves
      if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight) {
        await _keyboardHandler.handleModifierRelease('ctrl');
      } else if (event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight) {
        await _keyboardHandler.handleModifierRelease('alt');
      } else if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
          event.logicalKey == LogicalKeyboardKey.shiftRight) {
        await _keyboardHandler.handleModifierRelease('shift');
      } else if (event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight) {
        await _keyboardHandler.handleModifierRelease('meta');
      }
    }
  }

  String? _keyEventToString(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      return '\x08';
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      return '\n';
    } else if (event.logicalKey == LogicalKeyboardKey.tab) {
      return '\t';
    } else if (event.logicalKey == LogicalKeyboardKey.space) {
      return ' ';
    } else if (event.character != null && event.character!.isNotEmpty) {
      return event.character;
    } else if (event.logicalKey.keyLabel.length == 1) {
      return event.logicalKey.keyLabel;
    }
    return null;
  }

  Future<void> _handleTextInput(String text) async {
    if (!_isConnected) return;

    // Only process new characters
    if (text.length > _previousText.length) {
      final newChars = text.substring(_previousText.length);
      for (final char in newChars.runes) {
        final key = String.fromCharCode(char);
        await _keyboardHandler.handleKeyPress(key);
        await Future.delayed(const Duration(milliseconds: 10));
        await _keyboardHandler.handleKeyRelease(key);
      }
    } else if (text.length < _previousText.length) {
      // Handle backspace
      await _keyboardHandler.handleKeyPress('\x08');
      await Future.delayed(const Duration(milliseconds: 10));
      await _keyboardHandler.handleKeyRelease('\x08');
    }

    _previousText = text;
  }

  @override
  void dispose() {
    _physicalKeyboardFocusNode.dispose();
    _textFieldFocusNode.dispose();
    _textController.dispose();
    _commandService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _physicalKeyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Control - ${widget.server.address.address}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsScreen(settings: _settings),
                  ),
                );
                // Reload settings and recreate gesture handler with new config
                await _settings.load();
                _gestureConfig = GestureConfig(_settings);
                _initializeHandlers();
              },
            ),
          ],
        ),
        body: GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Container(
            color: Colors.grey[200],
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ValueListenableBuilder<ConnectionStatus>(
                          valueListenable: _commandService.status,
                          builder: (context, status, _) =>
                              _buildStatus(context, status),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'One finger: Move/Click\nTwo fingers: Right click/Scroll\nThree fingers: Middle click\nDouble tap: Select/Drag',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _textController,
                    focusNode: _textFieldFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Type here to send keyboard input...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      _handleTextInput(value);
                      _textController.clear();
                      _previousText = '';
                    },
                    onChanged: _handleTextInput,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
