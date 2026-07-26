import 'dart:async';
import 'dart:convert';

import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chat_service.dart';

/// Servidor realtime en Render (WebSocket).
class RealtimeConfig {
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

  static Uri get healthUri {
    final base = httpBase.trim().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base/health');
  }
}

/// Sala de videollamada + lobby personal para recibir llamadas.
class CallService {
  final _chatService = ChatService();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  String? _roomId;
  String? _userId;
  String? _role;

  // Lobby (recibir llamadas)
  WebSocketChannel? _lobbyChannel;
  StreamSubscription? _lobbySub;
  Timer? _lobbyPing;
  Timer? _lobbyReconnect;
  String? _lobbyUserId;
  void Function(Map<String, dynamic>)? _onInvite;
  Completer<void>? _lobbyReady;

  final _captionController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _peerController = StreamController<Map<String, dynamic>>.broadcast();
  final _signalController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _callEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get captions => _captionController.stream;
  Stream<Map<String, dynamic>> get peers => _peerController.stream;
  Stream<Map<String, dynamic>> get signals => _signalController.stream;
  Stream<Map<String, dynamic>> get callEvents => _callEventController.stream;

  bool get isConnected => _channel != null;
  bool get isLobbyConnected =>
      _lobbyChannel != null && _lobbyReady?.isCompleted == true;

  Future<Document> createOrJoinRoom({
    required String currentUserId,
    required String otherUserId,
  }) {
    return _chatService.resolveChat(
      userId: currentUserId,
      otherUserId: otherUserId,
    );
  }

  /// Despierta Render (free tier se duerme) antes de llamar.
  Future<bool> wakeServer() async {
    try {
      final res = await http
          .get(RealtimeConfig.healthUri)
          .timeout(const Duration(seconds: 20));
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (e) {
      debugPrint('wakeServer: $e');
      return false;
    }
  }

  /// Conecta al lobby personal `lobby:<userId>` para recibir invitaciones.
  Future<void> connectLobby({
    required String userId,
    required void Function(Map<String, dynamic>) onInvite,
  }) async {
    _lobbyUserId = userId;
    _onInvite = onInvite;
    await disconnectLobby(reconnect: false);

    final ready = Completer<void>();
    _lobbyReady = ready;

    try {
      debugPrint('Lobby connect ${RealtimeConfig.wsUri}');
      _lobbyChannel = WebSocketChannel.connect(RealtimeConfig.wsUri);
      await _lobbyChannel!.ready.timeout(const Duration(seconds: 12));

      _lobbySub = _lobbyChannel!.stream.listen(
        (raw) {
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            final type = msg['type']?.toString();
            if (type == 'welcome' || type == 'joined' || type == 'pong') {
              if (!ready.isCompleted) ready.complete();
            }
            if (type == 'invite') {
              _onInvite?.call(msg);
              _callEventController.add(msg);
            } else if (type == 'call_response') {
              _callEventController.add(msg);
            }
          } catch (e) {
            debugPrint('Lobby parse: $e');
          }
        },
        onError: (_) => _scheduleLobbyReconnect(),
        onDone: _scheduleLobbyReconnect,
        cancelOnError: false,
      );

      _lobbySend({
        'type': 'join',
        'roomId': 'lobby:$userId',
        'userId': userId,
        'role': 'lobby',
      });

      Future.delayed(const Duration(milliseconds: 800), () {
        if (!ready.isCompleted) ready.complete();
      });

      _lobbyPing?.cancel();
      _lobbyPing = Timer.periodic(const Duration(seconds: 25), (_) {
        _lobbySend({'type': 'ping'});
      });
    } catch (e) {
      debugPrint('Lobby connect failed: $e');
      if (!ready.isCompleted) ready.completeError(e);
      _scheduleLobbyReconnect();
    }
  }

  Future<void> ensureLobby({
    required String userId,
    required void Function(Map<String, dynamic>) onInvite,
  }) async {
    if (isLobbyConnected && _lobbyUserId == userId) return;
    await wakeServer();
    await connectLobby(userId: userId, onInvite: onInvite);
    try {
      await _lobbyReady?.future.timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _scheduleLobbyReconnect() {
    if (_lobbyUserId == null) return;
    _lobbyReconnect?.cancel();
    _lobbyReconnect = Timer(const Duration(seconds: 3), () {
      final uid = _lobbyUserId;
      final cb = _onInvite;
      if (uid != null && cb != null) {
        connectLobby(userId: uid, onInvite: cb);
      }
    });
  }

  void _lobbySend(Map<String, dynamic> data) {
    final ch = _lobbyChannel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  /// Envía invitación al lobby del destinatario.
  bool sendInvite({
    required String toUserId,
    required String fromUserId,
    required String fromName,
    required String roomId,
  }) {
    final payload = {
      'type': 'invite',
      'targetLobby': 'lobby:$toUserId',
      'toUserId': toUserId,
      'fromUserId': fromUserId,
      'fromName': fromName,
      'callRoomId': roomId,
      'roomId': roomId,
      'userId': fromUserId,
    };
    var sent = false;
    if (_lobbyChannel != null) {
      _lobbySend(payload);
      sent = true;
    }
    if (_channel != null) {
      _send(payload);
      sent = true;
    }
    if (!sent) {
      debugPrint('sendInvite: sin canal WS (lobby ni sala)');
    }
    return sent;
  }

  void sendCallResponse({
    required String toUserId,
    required String fromUserId,
    required String roomId,
    required bool accepted,
  }) {
    final msg = {
      'type': 'call_response',
      'targetLobby': 'lobby:$toUserId',
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'roomId': roomId,
      'accepted': accepted,
    };
    _lobbySend(msg);
    _send(msg);
  }

  Future<void> disconnectLobby({bool reconnect = true}) async {
    if (!reconnect) {
      _lobbyReconnect?.cancel();
      _lobbyUserId = null;
      _onInvite = null;
    }
    _lobbyPing?.cancel();
    await _lobbySub?.cancel();
    _lobbySub = null;
    try {
      await _lobbyChannel?.sink.close();
    } catch (_) {}
    _lobbyChannel = null;
    _lobbyReady = null;
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
        case 'invite':
        case 'call_response':
          _callEventController.add(msg);
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
    await disconnectLobby(reconnect: false);
    await disconnect();
    await _captionController.close();
    await _peerController.close();
    await _signalController.close();
    await _callEventController.close();
  }

  static String? parseCaption(String raw) => raw;
  static String? parseCaptionRole(String raw) => null;
}
