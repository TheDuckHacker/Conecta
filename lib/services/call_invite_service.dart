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
  DateTime? _lastRingAt;
  bool busyInCall = false;

  IncomingCall? get current => _last;

  Future<void> startListening({
    required String userId,
    required String userName,
  }) async {
    await stopListening();
    _myUserId = userId;
    // Por si quedó pegado de una llamada anterior en esta sesión
    busyInCall = false;

    try {
      _sub = realtime.subscribe([
        'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.usersCollectionId}.documents.$userId',
      ]);
      _sub!.stream.listen(
        (event) {
          try {
            final data = event.payload;
            final status = (data['status'] ?? '').toString();
            _handleStatus(status);
          } catch (e) {
            debugPrint('CallInvite realtime event: $e');
          }
        },
        onError: (e) => debugPrint('CallInvite realtime stream: $e'),
      );
    } catch (e) {
      debugPrint('CallInvite realtime: $e');
    }

    // Sondeo rápido: Appwrite Realtime falla a menudo en el cliente.
    _poll = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _pollStatus(),
    );

    await _connectLobbySafe(userId);
    await _pollStatus();
  }

  Future<void> _connectLobbySafe(String userId) async {
    try {
      await _calls.ensureLobby(
        userId: userId,
        onInvite: (msg) {
          final from = (msg['fromUserId'] ?? '').toString();
          final room = (msg['roomId'] ?? msg['callRoomId'] ?? '').toString();
          final name = (msg['fromName'] ?? 'Contacto').toString();
          if (from.isEmpty || room.isEmpty) return;
          if (from == _myUserId) return;
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

  /// Fuerza relectura (p. ej. al volver de segundo plano).
  Future<void> refreshIncoming() async {
    await _pollStatus();
    final me = _myUserId;
    if (me != null && !_calls.isLobbyConnected) {
      await _connectLobbySafe(me);
    }
  }

  void _handleStatus(String status) {
    if (busyInCall) return;
    var call = AuthService.parseIncomingCall(status);
    // Timbre viejo (quedó guardado de una llamada anterior): no molestar
    if (call != null && !AuthService.isFreshRinging(status)) {
      call = null;
    }
    if (call == null) {
      // No borrar una llamada reciente por un "online" intermedio (carrera
      // con lifecycle). Mantener ~45 s desde el último ring.
      if (_last != null) {
        final age = _lastRingAt == null
            ? const Duration(days: 1)
            : DateTime.now().difference(_lastRingAt!);
        if (age < const Duration(seconds: 45)) {
          return;
        }
        _last = null;
        _lastRingAt = null;
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
    if (same) {
      // Refrescar marca de tiempo para que el TTL no lo borre
      _lastRingAt = DateTime.now();
      return;
    }
    debugPrint(
      'Incoming call: ${call.fromName} (${call.fromUserId}) room=${call.roomId}',
    );
    _last = call;
    _lastRingAt = DateTime.now();
    _incomingController.add(call);
  }

  Future<String> startOutgoingCall({
    required String callerId,
    required String callerName,
    required String calleeId,
  }) async {
    // 1) Despertar Render + asegurar lobby del llamante
    await _calls.wakeServer();
    await _connectLobbySafe(callerId);

    final room = await _chat.resolveChat(
      userId: callerId,
      otherUserId: calleeId,
    );
    final roomId = room.$id;

    final encoded =
        Uri.encodeComponent(callerName.isEmpty ? 'Contacto' : callerName);
    final ringAt = DateTime.now().millisecondsSinceEpoch;
    final status = 'ringing:$callerId:$roomId:$encoded:$ringAt';

    // 2) Marcar ringing en el documento del destinatario (Appwrite)
    var statusOk = false;
    Object? statusError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: calleeId,
          data: {'status': status},
        );
        // Verificar que quedó escrito
        final check = await databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: calleeId,
        );
        if ((check.data['status'] ?? '').toString().startsWith('ringing:')) {
          statusOk = true;
          break;
        }
      } catch (e) {
        statusError = e;
        debugPrint('startOutgoingCall status try $attempt: $e');
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }

    // 3) Invite por WebSocket (inmediato si el otro está en lobby)
    final wsSent = _calls.sendInvite(
      toUserId: calleeId,
      fromUserId: callerId,
      fromName: callerName.isEmpty ? 'Contacto' : callerName,
      roomId: roomId,
    );

    // 4) Invite HTTP: el servidor lo guarda y lo entrega aunque el lobby
    // del otro se conecte un segundo después (fixea el bug de “ambos online”).
    final httpSent = await _calls.postInviteHttp(
      toUserId: calleeId,
      fromUserId: callerId,
      fromName: callerName.isEmpty ? 'Contacto' : callerName,
      roomId: roomId,
    );

    // Reintento WS un segundo después (por si el lobby recién despertó)
    Future.delayed(const Duration(seconds: 1), () {
      _calls.sendInvite(
        toUserId: calleeId,
        fromUserId: callerId,
        fromName: callerName.isEmpty ? 'Contacto' : callerName,
        roomId: roomId,
      );
      unawaited(_calls.postInviteHttp(
        toUserId: calleeId,
        fromUserId: callerId,
        fromName: callerName.isEmpty ? 'Contacto' : callerName,
        roomId: roomId,
      ));
    });

    if (!statusOk && !wsSent && !httpSent) {
      throw Exception(
        'No se pudo avisar al contacto. '
        'Revisa internet y que el otro tenga Conecta abierta. '
        '(${statusError ?? 'sin canal'})',
      );
    }

    if (!statusOk) {
      debugPrint(
        'startOutgoingCall: status Appwrite falló ($statusError); '
        'invite WS=$wsSent HTTP=$httpSent',
      );
    }

    return roomId;
  }

  /// Vuelve a timbrar mientras el llamante espera: cubre el caso de que el
  /// otro celular abra la app o recupere internet unos segundos después.
  Future<void> reRing({
    required String callerId,
    required String callerName,
    required String calleeId,
    required String roomId,
  }) async {
    final name = callerName.isEmpty ? 'Contacto' : callerName;
    final encoded = Uri.encodeComponent(name);
    final ringAt = DateTime.now().millisecondsSinceEpoch;

    try {
      final doc = await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: calleeId,
      );
      final current = (doc.data['status'] ?? '').toString();
      // Si ya contestó (in_call) no volver a timbrar
      if (current.startsWith('in_call:')) return;
      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: calleeId,
        data: {'status': 'ringing:$callerId:$roomId:$encoded:$ringAt'},
      );
    } catch (e) {
      debugPrint('reRing status: $e');
    }

    _calls.sendInvite(
      toUserId: calleeId,
      fromUserId: callerId,
      fromName: name,
      roomId: roomId,
    );
    unawaited(_calls.postInviteHttp(
      toUserId: calleeId,
      fromUserId: callerId,
      fromName: name,
      roomId: roomId,
    ));
  }

  Future<void> acceptCall(IncomingCall call) async {
    busyInCall = true;
    _last = null;
    _lastRingAt = null;
    _incomingController.add(null);
    final me = _myUserId;
    if (me != null) {
      await _setStatus(me, 'in_call:${call.roomId}');
    }
    // Avisar al llamante que contestaron (además de entrar a la sala)
    _calls.sendCallResponse(
      toUserId: call.fromUserId,
      fromUserId: me ?? '',
      roomId: call.roomId,
      accepted: true,
    );
  }

  Future<void> rejectCall(IncomingCall call) async {
    busyInCall = false;
    final me = _myUserId;
    if (me != null) {
      await _forceStatus(me, 'online');
    }
    _calls.sendCallResponse(
      toUserId: call.fromUserId,
      fromUserId: me ?? '',
      roomId: call.roomId,
      accepted: false,
    );
    _last = null;
    _lastRingAt = null;
    _incomingController.add(null);
  }

  Future<void> markInCall(String userId, String roomId) async {
    busyInCall = true;
    await _setStatus(userId, 'in_call:$roomId');
  }

  Future<void> endCall(String userId) async {
    busyInCall = false;
    await _forceStatus(userId, 'online');
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
        await _forceStatus(calleeId, 'online');
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

  /// Fuerza status aunque haya ringing (colgar / rechazar / fin de llamada).
  Future<void> _forceStatus(String userId, String status) async {
    try {
      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
        data: {'status': status},
      );
    } catch (e) {
      debugPrint('forceStatus: $e');
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
