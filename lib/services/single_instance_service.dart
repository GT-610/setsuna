import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/logging.dart';

enum SingleInstanceAcquireResult {
  acquired,
  existingInstanceActivated,
  unconfirmedConflict,
}

/// Coordinates one running Setsuna process per user session.
class SingleInstanceService with Loggable {
  SingleInstanceService({int port = _DEFAULT_PORT}) : _port = port;

  static final SingleInstanceService instance = SingleInstanceService();

  // ignore: constant_identifier_names
  static const int _DEFAULT_PORT = 47621;
  // ignore: constant_identifier_names
  static const String _ACTIVATION_MESSAGE = 'setsuna.activate';
  // ignore: constant_identifier_names
  static const String _ACTIVATION_ACKNOWLEDGEMENT = 'setsuna.ack';

  final int _port;
  ServerSocket? _server;
  Future<void> Function()? _onActivate;
  bool _activationPending = false;

  bool get isPrimary => _server != null;

  int get port => _server?.port ?? _port;

  Future<SingleInstanceAcquireResult> acquire() async {
    if (_server != null) {
      return SingleInstanceAcquireResult.acquired;
    }

    try {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _port,
        shared: false,
      );
      _server = server;
      server.listen(_handleConnection);
      return SingleInstanceAcquireResult.acquired;
    } on SocketException catch (error, stackTrace) {
      w(
        'Another Setsuna process may already be running',
        error: error,
        stackTrace: stackTrace,
      );
      if (await _activatePrimary()) {
        return SingleInstanceAcquireResult.existingInstanceActivated;
      }

      w('Could not confirm the single-instance activation request');
      return SingleInstanceAcquireResult.unconfirmedConflict;
    }
  }

  void setOnActivate(Future<void> Function()? callback) {
    _onActivate = callback;
    if (callback != null && _activationPending) {
      _activationPending = false;
      unawaited(_invokeActivationCallback(callback));
    }
  }

  Future<void> release() async {
    final server = _server;
    _server = null;
    await server?.close();
  }

  Future<bool> _activatePrimary() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(milliseconds: 800),
      );
      socket.write('$_ACTIVATION_MESSAGE\n');
      await socket.flush();
      final acknowledgement = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(milliseconds: 800));
      return acknowledgement == _ACTIVATION_ACKNOWLEDGEMENT;
    } catch (error, stackTrace) {
      w(
        'Failed to contact the running Setsuna process',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _handleConnection(Socket socket) async {
    try {
      final message = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 1));
      if (message != _ACTIVATION_MESSAGE) {
        return;
      }

      socket.write('$_ACTIVATION_ACKNOWLEDGEMENT\n');
      await socket.flush();
      final callback = _onActivate;
      if (callback == null) {
        _activationPending = true;
      } else {
        unawaited(_invokeActivationCallback(callback));
      }
    } catch (error, stackTrace) {
      w(
        'Failed to process a single-instance activation request',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      socket.destroy();
    }
  }

  Future<void> _invokeActivationCallback(
    Future<void> Function() callback,
  ) async {
    try {
      await callback();
    } catch (error, stackTrace) {
      e(
        'Failed to activate the existing Setsuna window',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
