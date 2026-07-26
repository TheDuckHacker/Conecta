import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'auth_service.dart';
import 'call_service.dart';
import 'chat_service.dart';

typedef IncomingCall = IncomingCallInfo;

/// Gestión de llamar / recibir llamada entre dos usuarios.
///
/// Convención en `users.status` del destinatario:
///   ringing:<fromUserId>:<roomId>:<nombreCodificado>
///
/// También usa el lobby WebSocket `lobby:<userId>` para aviso inmediato.
class CallInviteService {
  CallInviteService._();
  static final CallInviteService instance = CallInviteService._();

  final _auth = AuthService();
  final _chat = ChatService();
  final _calls = CallService();

  final _incomingController = StreamController<IncomingCall?>.broadcast();
  Stream<IncomingCall?> get incoming => _incomingController.stream;
  Stream<Map<String, dynamic>> get callEvents => _calls.callEvents;

  RealtimeSubscription? _sub;
  Timer? _poll;
  StreamSubscription? _lobbySub;
  String? _myUserId;
  IncomingCall? _last;
  bool busyInCall = false;

  IncomingCall? get current => _last;

  Future<void> startListening({
    required String userId,
    required String userName,
  }) async {
    await stopListening();
    _myUserId = userId;

    try {
      _sub = realtime.subscribe([
        'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.usersCollectionId}.documents.$userId',
      ]);
      _sub!.stream.listen((event) {
        final data = event.payload;
        final status = (data['status'] ?? '').toString();
        _handleStatus(status);
      });
    } catch (e) {
      debugPrint('CallInvite realtime: $e');
    }

    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus());

    try {
      await _calls.connectLobby(
        userId: userId,
        onInvite: (msg) {
          final from = (msg['fromUserId'] ?? '').toString();
          final room = (msg['roomId'] ?? msg['callRoomId'] ?? '').toString();
          final name = (msg['fromName'] ?? 'Contacto').toString();
          if (from.isEmpty || room.isEmpty) return;
          _emit(IncomingCall(
            fromUserId: from,
            fromName: name,
            roomId: room,
            rawStatus: 'ringing:$from:$room:${Uri.encodeComponent(name)}',
          ));
        },
      );
    } catch (e) {
      debugPrint('CallInvite lobby: $e');
    }

    await _pollStatus();
  }

  Future<void> _pollStatus() async {
    final me = _myUserId;
    if (me == null || busyInCall) return;
    try {
      final doc = await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: me,
      );
      _handleStatus((doc.data['status'] ?? '').toString());
    } catch (_) {}
  }

  void _handleStatus(String status) {
    if (busyInCall) return;
    final call = AuthService.parseIncomingCall(status);
    if (call == null) {
      if (_last != null) {
        _last = null;
        _incomingController.add(null);
      }
      return;
    }
    if (call.fromUserId == _myUserId) return;
    _emit(call);
  }

  void _emit(IncomingCall call) {
    final same = _last != null &&
        _last!.fromUserId == call.fromUserId &&
        _last!.roomId == call.roomId;
    if (same) return;
    _last = call;
    _incomingController.add(call);
  }

  Future<String> startOutgoingCall({
    required String callerId,
    required String callerName,
    required String calleeId,
  }) async {
    final room = await _chat.resolveChat(
      userId: callerId,
      otherUserId: calleeId,
    );
    final roomId = room.$id;

    final encoded =
        Uri.encodeComponent(callerName.isEmpty ? 'Contacto' : callerName);
    final status = 'ringing:$callerId:$roomId:$encoded';

    try {
      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: calleeId,
        data: {'status': status},
      );
    } catch (e) {
      debugPrint('startOutgoingCall status: $e');
    }

    _calls.sendInvite(
      toUserId: calleeId,
      fromUserId: callerId,
      fromName: callerName.isEmpty ? 'Contacto' : callerName,
      roomId: roomId,
    );

    return roomId;
  }

  Future<void> acceptCall(IncomingCall call) async {
    busyInCall = true;
    _last = null;
    _incomingController.add(null);
    final me = _myUserId;
    if (me != null) {
      await _setStatus(me, 'in_call:${call.roomId}');
    }
  }

  Future<void> rejectCall(IncomingCall call) async {
    final me = _myUserId;
    if (me != null) {
      await _auth.setOnlineStatus(me, true);
    }
    _calls.sendCallResponse(
      toUserId: call.fromUserId,
      fromUserId: me ?? '',
      roomId: call.roomId,
      accepted: false,
    );
    _last = null;
    _incomingController.add(null);
  }

  Future<void> markInCall(String userId, String roomId) async {
    busyInCall = true;
    await _setStatus(userId, 'in_call:$roomId');
  }

  Future<void> endCall(String userId) async {
    busyInCall = false;
    await _auth.setOnlineStatus(userId, true);
  }

  Future<void> clearRingingOnCallee(String calleeId) async {
    try {
      final doc = await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: calleeId,
      );
      final status = (doc.data['status'] ?? '').toString();
      if (status.startsWith('ringing:')) {
        await _auth.setOnlineStatus(calleeId, true);
      }
    } catch (_) {}
  }

  Future<void> _setStatus(String userId, String status) async {
    try {
      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
        data: {'status': status},
      );
    } catch (e) {
      debugPrint('setStatus: $e');
    }
  }

  Future<void> stopListening() async {
    _poll?.cancel();
    _poll = null;
    try {
      await _sub?.close();
    } catch (_) {}
    _sub = null;
    await _lobbySub?.cancel();
    _lobbySub = null;
    await _calls.disconnectLobby();
  }
}
