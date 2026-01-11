import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../domain/models/touch_action.dart';
import '../../../domain/models/gesture_event.dart';
import '../state/gesture_state.dart';
import '../config/gesture_config.dart';
import '../../mouse_control/interfaces/mouse_command_executor.dart';

class MoveHandler {
  final GestureState _state;
  final MouseCommandExecutor _executor;
  final GestureConfig _config;

  MoveHandler(this._state, this._executor, this._config);

  Future<void> handle(GestureEvent event) async {
    if (_state.previousTapAction == TouchAction.none) return;
    if (_state.isInRightClickCooldown()) return;

    final dx = event.x - _state.previousX;
    final dy = event.y - _state.previousY;

    if (_state.previousTouchAction != TouchAction.move) {
      await _handleFirstMovement(dx, dy, event);
      return;
    }

    await _handleContinuousMovement(dx, dy, event);
  }

  Future<void> _handleFirstMovement(double dx, double dy, GestureEvent event) async {
    final deadzone = _isScrolling() ? _config.deadZoneScroll : _config.deadZoneInitial;
    final withinDeadzone = dx.abs() <= deadzone && dy.abs() <= deadzone;

    if (withinDeadzone) return;

    _state.moving = true;
    _state.waitingForSecondTap = false;
    _state.previousX = event.x;
    _state.previousY = event.y;
  }

  Future<void> _handleContinuousMovement(double dx, double dy, GestureEvent event) async {
    if (dx.abs() > 0 || dy.abs() > 0) {
      _state.moving = true;
      _state.movedSinceLastDown = true;
    }

    if (_isScrolling()) {
      await _handleScroll(dx, dy, event);
      return;
    }

    await _handleMouseMove(dx, dy, event);
  }

  bool _isScrolling() => _state.previousTapAction == TouchAction.pointer2Down;

  Future<void> _handleScroll(double dx, double dy, GestureEvent event) async {
    final withinDeadzone =
        _config.deadZoneScroll > dx.abs() && _config.deadZoneScroll > dy.abs();

    if (withinDeadzone) return;

    _state.scrolling = true;
    final scrollAmount = dy * _config.scrollSpeed;
    await _executor.mouseScroll(0, scrollAmount);
    _state.previousX = event.x;
    _state.previousY = event.y;
  }

  Future<void> _handleMouseMove(double dx, double dy, GestureEvent event) async {
    final acceleration = _calculateAcceleration(dx, dy);
    final moveX = dx * _config.mouseSensitivity * acceleration;
    final moveY = dy * _config.mouseSensitivity * acceleration;

    if (kDebugMode) {
      print('[CLIENT] mouseMove: dx=$dx dy=$dy -> moveX=${moveX.toStringAsFixed(2)} moveY=${moveY.toStringAsFixed(2)}');
    }
    await _executor.mouseMove(moveX, moveY);
    _state.previousX = event.x;
    _state.previousY = event.y;
    _state.lastMoveTime = DateTime.now();
  }

  double _calculateAcceleration(double dx, double dy) {
    if (_state.lastMoveTime == null) return _config.minAcceleration;

    final now = DateTime.now();
    final timeDelta = now.difference(_state.lastMoveTime!).inMilliseconds;

    final isInvalidTimeDelta = timeDelta <= 0 || timeDelta >= 100;
    if (isInvalidTimeDelta) return _config.minAcceleration;

    final distance = sqrt(dx * dx + dy * dy);
    if (distance == 0) return _config.minAcceleration;

    final velocity = distance / timeDelta;
    final velocityRatio = (velocity / _config.accelerationThreshold).clamp(0.0, 1.0);
    final smoothedRatio = sqrt(velocityRatio);

    return _config.minAcceleration +
        (_config.maxAcceleration - _config.minAcceleration) * smoothedRatio;
  }
}
