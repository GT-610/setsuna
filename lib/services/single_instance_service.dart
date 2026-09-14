import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/logging.dart';

/// Coordinates one running Setsuna process per user session.
class SingleInstanceService with Loggable {
  SingleInstanceService({int port = _defaultPort}) : _port = port;

  static final SingleInstanceService instance = SingleInstanceService();

  static const int _defaultPort = 47621;
  static const String _activationMessage = 'setsuna.activate';
  static const String _activationAcknowledgement = 'setsuna.ack';

  final int _port;
  ServerSocket? _server;
  Future<void> Function()? _onActivate;
  bool _activationPending = false;

  bool get isPrimary => _server != null;

  int get port => _server?.port ?? _port;

  Future<bool> acquire() async {
    if (_server != null) {
      return true;
    }

    try {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _port,
        shared: false,
      );
      _server = server;
      server.listen(_handleConnection);
      return true;
    } on SocketException catch (error, stackTrace) {
      w(
        'Another Setsuna process may already be running',
        error: error,
        stackTrace: stackTrace,
      );
      return !(await _activatePrimary());
    }
  }

  void setOnActivate(Future<void> Function()? callback) {
    _onActivate = callback;
    if (callback != null && _activationPending) {
      _activationPending = false;
      unawaited(callback());
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
      socket.write('$_activationMessage\n');
      await socket.flush();
      final acknowledgement = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(milliseconds: 800));
      return acknowledgement == _activationAcknowledgement;
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
      if (message != _activationMessage) {
        return;
      }

      socket.write('$_activationAcknowledgement\n');
      await socket.flush();
      final callback = _onActivate;
      if (callback == null) {
        _activationPending = true;
      } else {
        unawaited(callback());
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
}
