import 'dart:async';
import 'dart:convert';

import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chat_service.dart';

/// Servidor realtime en Render (WebSocket).
class RealtimeConfig {
  /// URL pública del servicio en Render (sin /ws).
  /// Se actualiza al desplegar; también se puede pasar con --dart-define.
  static const String httpBase = String.fromEnvironment(
    'CONECTA_REALTIME_URL',
    defaultValue: 'https://conecta-realtime.onrender.com',
  );

  static Uri get wsUri {
    final base = httpBase.trim().replaceAll(RegExp(r'/$'), '');
    final ws = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return Uri.parse('$ws/ws');
  }
}

/// Sala de videollamada accesible vía Render WebSocket (tiempo real).
class CallService {
  final _chatService = ChatService();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  String? _roomId;
  String? _userId;
  String? _role;

  final _captionController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _peerController = StreamController<Map<String, dynamic>>.broadcast();
  final _signalController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get captions => _captionController.stream;
  Stream<Map<String, dynamic>> get peers => _peerController.stream;
  Stream<Map<String, dynamic>> get signals => _signalController.stream;

  bool get isConnected => _channel != null;

  Future<Document> createOrJoinRoom({
    required String currentUserId,
    required String otherUserId,
  }) {
    return _chatService.resolveChat(
      userId: currentUserId,
      otherUserId: otherUserId,
    );
  }

  Future<void> connect({
    required String roomId,
    required String userId,
    String role = 'unknown',
  }) async {
    await disconnect(sendLeave: false);
    _roomId = roomId;
    _userId = userId;
    _role = role;

    try {
      debugPrint('Realtime connect ${RealtimeConfig.wsUri}');
      _channel = WebSocketChannel.connect(RealtimeConfig.wsUri);
      await _channel!.ready.timeout(const Duration(seconds: 12));

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('WS error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WS closed');
          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      _send({
        'type': 'join',
        'roomId': roomId,
        'userId': userId,
        'role': role,
      });

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'type': 'ping'});
      });
    } catch (e) {
      debugPrint('Realtime connect failed: $e');
      _scheduleReconnect();
      rethrow;
    }
  }

  void _scheduleReconnect() {
    if (_roomId == null || _userId == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_roomId != null && _userId != null) {
        connect(
          roomId: _roomId!,
          userId: _userId!,
          role: _role ?? 'unknown',
        );
      }
    });
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type']?.toString();
      switch (type) {
        case 'caption':
          _captionController.add(msg);
          break;
        case 'peer_joined':
        case 'peer_left':
        case 'joined':
          _peerController.add(msg);
          break;
        case 'signal':
          _signalController.add(msg);
          break;
        case 'pong':
        case 'welcome':
          break;
        case 'error':
          debugPrint('Realtime server error: ${msg['message']}');
          break;
      }
    } catch (e) {
      debugPrint('WS parse: $e');
    }
  }

  void _send(Map<String, dynamic> data) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('WS send: $e');
    }
  }

  Future<void> sendCaption({
    required String roomId,
    required String senderId,
    required String text,
    required String role,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _send({
      'type': 'caption',
      'roomId': roomId,
      'userId': senderId,
      'text': clean,
      'role': role,
    });
  }

  void sendSignal({
    required String roomId,
    required String userId,
    required Map<String, dynamic> payload,
    String? to,
  }) {
    _send({
      'type': 'signal',
      'roomId': roomId,
      'userId': userId,
      'to': to,
      'payload': payload,
    });
  }

  Future<void> disconnect({bool sendLeave = true}) async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    if (sendLeave && _roomId != null && _userId != null) {
      _send({
        'type': 'leave',
        'roomId': _roomId,
        'userId': _userId,
      });
    }
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _captionController.close();
    await _peerController.close();
    await _signalController.close();
  }

  // Compat API antigua (ya no usa Appwrite para captions)
  static String? parseCaption(String raw) => raw;
  static String? parseCaptionRole(String raw) => null;
}
