import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_service.dart';

/// Videollamada WebRTC real (P2P) usando el WebSocket de Conecta como señalización.
///
/// Negociación simple y estable:
/// - Solo el [isCaller] crea ofertas.
/// - El que contesta solo responde (answer).
/// - El caller reintenta el offer hasta recibir answer / conectar.
class WebRtcCallSession {
  WebRtcCallSession({
    required this.calls,
    required this.roomId,
    required this.localUserId,
    required this.isCaller,
    /// En modo sordo la cámara la usa ML Kit; WebRTC solo lleva audio.
    this.enableLocalVideo = true,
  });

  final CallService calls;
  final String roomId;
  final String localUserId;
  final bool isCaller;
  final bool enableLocalVideo;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription? _signalSub;
  bool _makingOffer = false;
  bool _disposed = false;
  bool _remoteDescriptionSet = false;
  bool _answered = false;
  bool _peerSeen = false;
  Timer? _offerRetry;
  final _pendingCandidates = <RTCIceCandidate>[];
  final _earlySignals = <Map<String, dynamic>>[];

  final _remoteReady = ValueNotifier<bool>(false);
  final _localReady = ValueNotifier<bool>(false);
  ValueListenable<bool> get remoteReady => _remoteReady;
  ValueListenable<bool> get localReady => _localReady;

  void _setRemoteReady(bool value) {
    if (_disposed) return;
    try {
      _remoteReady.value = value;
    } catch (_) {}
  }

  void _setLocalReady(bool value) {
    if (_disposed) return;
    try {
      _localReady.value = value;
    } catch (_) {}
  }

  bool get canRenderLocal =>
      !_disposed &&
      localRenderer.textureId != null &&
      localRenderer.srcObject != null;

  bool get canRenderRemote =>
      !_disposed &&
      remoteRenderer.textureId != null &&
      remoteRenderer.srcObject != null;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  Future<void> start() async {
    // Escuchar señales YA (por si el offer llega mientras abrimos cámara)
    _signalSub = calls.signals.listen(_onSignal);

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': enableLocalVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            }
          : false,
    });
    localRenderer.onFirstFrameRendered = () => _setLocalReady(canRenderLocal);
    remoteRenderer.onFirstFrameRendered =
        () => _setRemoteReady(canRenderRemote);
    remoteRenderer.onResize = () => _setRemoteReady(canRenderRemote);

    if (enableLocalVideo) {
      localRenderer.srcObject = _localStream;
      _setLocalReady(canRenderLocal);
    }

    _pc = await createPeerConnection(_iceServers, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      calls.sendSignal(
        roomId: roomId,
        userId: localUserId,
        payload: {
          'type': 'ice',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      if (_disposed || event.streams.isEmpty) return;
      try {
        remoteRenderer.srcObject = event.streams[0];
        _setRemoteReady(true);
      } catch (e) {
        debugPrint('onTrack render: $e');
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('WebRTC connection: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _answered = true;
        _offerRetry?.cancel();
        _setRemoteReady(canRenderRemote);
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _setRemoteReady(false);
      }
    };

    // Procesar señales que llegaron antes de tener PC
    final early = List<Map<String, dynamic>>.from(_earlySignals);
    _earlySignals.clear();
    for (final msg in early) {
      await _onSignal(msg);
    }

    if (_peerSeen && isCaller) {
      await _createAndSendOffer();
      _startOfferRetry();
    }
  }

  /// Solo el llamante crea ofertas. El que contesta solo hace answer.
  Future<void> onPeerJoined() async {
    if (_disposed) return;
    _peerSeen = true;
    if (!isCaller) return;
    await _createAndSendOffer();
    _startOfferRetry();
  }

  void _startOfferRetry() {
    if (!isCaller || _disposed) return;
    _offerRetry?.cancel();
    _offerRetry = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (_disposed || _answered) {
        t.cancel();
        return;
      }
      debugPrint('WebRTC: reenviando offer…');
      await _createAndSendOffer();
    });
  }

  Future<void> _createAndSendOffer() async {
    final pc = _pc;
    if (pc == null || _disposed || _makingOffer || !isCaller) return;
    if (_answered) return;
    _makingOffer = true;
    try {
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await pc.setLocalDescription(offer);
      calls.sendSignal(
        roomId: roomId,
        userId: localUserId,
        payload: {
          'type': 'offer',
          'sdp': offer.sdp,
          'sdpType': offer.type,
        },
      );
      debugPrint('WebRTC: offer enviado');
    } catch (e) {
      debugPrint('WebRTC offer: $e');
    } finally {
      _makingOffer = false;
    }
  }

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    if (_disposed) return;
    final from = msg['userId']?.toString() ?? '';
    if (from.isEmpty || from == localUserId) return;

    final pc = _pc;
    if (pc == null) {
      if (_earlySignals.length < 40) _earlySignals.add(msg);
      return;
    }

    final payload = msg['payload'];
    if (payload is! Map) return;
    final map = Map<String, dynamic>.from(payload);
    final type = map['type']?.toString();

    try {
      switch (type) {
        case 'offer':
          // El caller ignora offers ajenos (evita glare)
          if (isCaller) {
            debugPrint('WebRTC: ignorando offer (somos caller)');
            return;
          }
          await _handleRemoteOffer(pc, map);
          break;
        case 'answer':
          if (!isCaller) return;
          final state = pc.signalingState;
          if (state !=
              RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            debugPrint('WebRTC: answer fuera de estado ($state)');
            return;
          }
          await pc.setRemoteDescription(
            RTCSessionDescription(
              map['sdp']?.toString(),
              map['sdpType']?.toString() ?? 'answer',
            ),
          );
          _remoteDescriptionSet = true;
          _answered = true;
          _offerRetry?.cancel();
          await _drainCandidates();
          debugPrint('WebRTC: answer aplicado');
          break;
        case 'ice':
          final c = RTCIceCandidate(
            map['candidate']?.toString(),
            map['sdpMid']?.toString(),
            map['sdpMLineIndex'] is int
                ? map['sdpMLineIndex'] as int
                : int.tryParse('${map['sdpMLineIndex']}'),
          );
          if (_remoteDescriptionSet) {
            await pc.addCandidate(c);
          } else {
            _pendingCandidates.add(c);
          }
          break;
      }
    } catch (e) {
      debugPrint('WebRTC signal $type: $e');
    }
  }

  Future<void> _handleRemoteOffer(
    RTCPeerConnection pc,
    Map<String, dynamic> map,
  ) async {
    final state = pc.signalingState;
    // Si ya contestamos, ignorar offers duplicados
    if (_answered &&
        state == RTCSignalingState.RTCSignalingStateStable) {
      debugPrint('WebRTC: offer duplicado ignorado');
      return;
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(
        map['sdp']?.toString(),
        map['sdpType']?.toString() ?? 'offer',
      ),
    );
    _remoteDescriptionSet = true;
    await _drainCandidates();

    final answer = await pc.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await pc.setLocalDescription(answer);
    calls.sendSignal(
      roomId: roomId,
      userId: localUserId,
      payload: {
        'type': 'answer',
        'sdp': answer.sdp,
        'sdpType': answer.type,
      },
    );
    _answered = true;
    debugPrint('WebRTC: answer enviado');
  }

  Future<void> _drainCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in _pendingCandidates) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  Future<void> setMicEnabled(bool enabled) async {
    for (final t in _localStream?.getAudioTracks() ?? []) {
      t.enabled = enabled;
    }
  }

  Future<void> setCamEnabled(bool enabled) async {
    for (final t in _localStream?.getVideoTracks() ?? []) {
      t.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      debugPrint('switchCamera: $e');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _setLocalReady(false);
    _setRemoteReady(false);
    _disposed = true;
    _offerRetry?.cancel();
    _offerRetry = null;

    await _signalSub?.cancel();
    _signalSub = null;
    localRenderer.onFirstFrameRendered = null;
    remoteRenderer.onFirstFrameRendered = null;
    remoteRenderer.onResize = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    for (final t in _localStream?.getTracks() ?? []) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      localRenderer.srcObject = null;
    } catch (_) {}
    try {
      remoteRenderer.srcObject = null;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 32));
    try {
      await localRenderer.dispose();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}
