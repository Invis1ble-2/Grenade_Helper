import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/overlay_snapshot.dart';

typedef OverlayCommandHandler = FutureOr<void> Function(
  String command,
  Map<String, dynamic>? args,
);

class OverlayIpcClient {
  final int port;
  final String token;

  WebSocket? _socket;
  OverlayCommandHandler? onCommand;
  VoidCallback? onDisconnected;

  OverlayIpcClient({
    required this.port,
    required this.token,
  });

  static ({int port, String token})? parseArgs(List<String> args) {
    int? port;
    String? token;
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i] == '--port') {
        port = int.tryParse(args[i + 1]);
      } else if (args[i] == '--token') {
        token = args[i + 1];
      }
    }
    if (port == null || token == null || token.isEmpty) return null;
    return (port: port, token: token);
  }

  Future<OverlayInitConfig> connectAndAwaitInit() async {
    final uri = Uri(
      scheme: 'ws',
      host: '127.0.0.1',
      port: port,
      queryParameters: {'token': token},
    );

    final socket = await WebSocket.connect(uri.toString());
    _socket = socket;

    final initCompleter = Completer<OverlayInitConfig>();

    socket.listen(
      (raw) {
        if (raw is! String) return;
        final dynamic decoded = jsonDecode(raw);
        if (decoded is! Map) return;
        final cmd = decoded['cmd'] as String?;
        if (cmd == null) return;
        final args = decoded['args'] is Map
            ? Map<String, dynamic>.from(decoded['args'] as Map)
            : null;

        if (cmd == 'init' && !initCompleter.isCompleted && args != null) {
          initCompleter.complete(OverlayInitConfig.fromJson(args));
          return;
        }
        onCommand?.call(cmd, args);
      },
      onDone: () {
        if (!initCompleter.isCompleted) {
          initCompleter.completeError(StateError('IPC closed before init'));
        }
        onDisconnected?.call();
      },
      onError: (Object error) {
        if (!initCompleter.isCompleted) {
          initCompleter.completeError(error);
        }
        onDisconnected?.call();
      },
      cancelOnError: true,
    );

    return initCompleter.future.timeout(const Duration(seconds: 10));
  }

  void sendEvent(String event, [Map<String, dynamic>? args]) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode({
      'event': event,
      if (args != null) 'args': args,
    }));
  }

  Future<void> close() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

typedef VoidCallback = void Function();
