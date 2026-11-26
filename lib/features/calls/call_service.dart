import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/config/app_config.dart';
import '../../core/config/device_id.dart';
import '../../core/crypto/crypto_engine.dart';
import '../../core/supabase/supabase_service.dart';

enum CallState { idle, calling, ringing, connected, ended }

/// One-to-one encrypted audio/video calling.
///
/// Media travels peer-to-peer over WebRTC (DTLS-SRTP encrypted). The signaling (SDP/ICE) is
/// additionally end-to-end encrypted with the same Signal session used for chat and relayed
/// through the `call_signals` table on Supabase. The server sees only ciphertext.
class CallService {
  CallService(this._supabase);
  final SupabaseService _supabase;
  final _crypto = CryptoEngine.instance;

  final state = ValueNotifier<CallState>(CallState.idle);
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription? _signalSub;
  final _handled = <String>{};

  // Current peer.
  String? _peerUserId;
  String? _peerDeviceId;
  String? _conversationId;
  bool _video = true;

  bool _inited = false;
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _listenForSignals();
  }

  Map<String, dynamic> get _config => {
        'iceServers': AppConfig.iceServers.isEmpty
            ? [
                {'urls': 'stun:stun.l.google.com:19302'}
              ]
            : (jsonDecode(AppConfig.iceServers) as List),
        'sdpSemantics': 'unified-plan',
      };

  // ───────────────────────── outgoing call ─────────────────────────
  Future<void> startCall({
    required String conversationId,
    required String peerUserId,
    required String peerDeviceId,
    bool video = true,
  }) async {
    _conversationId = conversationId;
    _peerUserId = peerUserId;
    _peerDeviceId = peerDeviceId;
    _video = video;
    state.value = CallState.calling;

    await _crypto.ensureReady(_supabase);
    await _createPeer();

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await _send('offer', jsonEncode({'sdp': offer.sdp, 'type': offer.type}));
  }

  // ───────────────────────── incoming call accept ─────────────────────────
  Future<void> _onOffer(Map<String, dynamic> data) async {
    await _createPeer();
    await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _send('answer', jsonEncode({'sdp': answer.sdp, 'type': answer.type}));
    state.value = CallState.connected;
  }

  Future<void> _createPeer() async {
    _pc = await createPeerConnection(_config);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': _video ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = _localStream;
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _send('ice', jsonEncode({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      }));
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        state.value = CallState.connected;
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangup(local: false);
      }
    };
  }

  // ───────────────────────── signaling I/O ─────────────────────────
  Future<void> _send(String kind, String payloadPlaintext) async {
    final me = _supabase.currentUser!.id;
    final tenantId = await _supabase.currentTenantId();
    final myDevice = await DeviceId.get();
    final address = await _crypto.sessions.ensureSession(_peerUserId!, _peerDeviceId!);
    final env = await _crypto.e2e.encryptText(address, payloadPlaintext);

    await _supabase.client.from('call_signals').insert({
      'tenant_id': tenantId,
      'conversation_id': _conversationId,
      'from_user': me,
      'to_user': _peerUserId,
      'kind': kind,
      // sender device id is non-secret (random per install) and needed to pick the session.
      'payload_enc': jsonEncode({'dev': myDevice, 'env': env}),
    });
  }

  void _listenForSignals() {
    final me = _supabase.currentUser?.id;
    if (me == null) return;
    _signalSub = _supabase.client
        .from('call_signals')
        .stream(primaryKey: ['id'])
        .eq('to_user', me)
        .order('created_at')
        .listen((rows) async {
          for (final r in rows) {
            final id = r['id'] as String;
            if (_handled.contains(id)) continue;
            _handled.add(id);
            await _handleSignal(r);
          }
        });
  }

  Future<void> _handleSignal(Map<String, dynamic> r) async {
    await _crypto.ensureReady(_supabase);
    final fromUser = r['from_user'] as String;
    final kind = r['kind'] as String;
    final wrap = jsonDecode(r['payload_enc'] as String) as Map<String, dynamic>;
    final fromDevice = wrap['dev'] as String;

    // On receive we don't build a session from a bundle: decryptText establishes it from a
    // PreKey message, or uses the existing session for whisper messages (answer/ice).
    final address = _crypto.sessions.addressFor(fromUser, fromDevice);
    final plaintext = await _crypto.e2e.decryptText(address, wrap['env'] as String);
    final data = jsonDecode(plaintext) as Map<String, dynamic>;

    switch (kind) {
      case 'offer':
        _conversationId = r['conversation_id'] as String;
        _peerUserId = fromUser;
        _peerDeviceId = fromDevice;
        state.value = CallState.ringing;
        // Auto-answer is not done here; the UI calls acceptIncoming() which runs _onOffer.
        _pendingOffer = data;
        break;
      case 'answer':
        await _pc?.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
        state.value = CallState.connected;
        break;
      case 'ice':
        await _pc?.addCandidate(RTCIceCandidate(
          data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        break;
      case 'hangup':
        await hangup(local: false);
        break;
    }
  }

  Map<String, dynamic>? _pendingOffer;

  /// UI calls this to answer a ringing call.
  Future<void> acceptIncoming({bool video = true}) async {
    _video = video;
    if (_pendingOffer != null) {
      await _onOffer(_pendingOffer!);
      _pendingOffer = null;
    }
  }

  // ───────────────────────── controls ─────────────────────────
  Future<void> toggleMute() async {
    final audio = _localStream?.getAudioTracks();
    if (audio != null && audio.isNotEmpty) {
      audio.first.enabled = !audio.first.enabled;
    }
  }

  Future<void> switchCamera() async {
    final video = _localStream?.getVideoTracks();
    if (video != null && video.isNotEmpty) {
      await Helper.switchCamera(video.first);
    }
  }

  Future<void> hangup({bool local = true}) async {
    if (local && _peerUserId != null) {
      try {
        await _send('hangup', '{}');
      } catch (_) {}
    }
    await _localStream?.dispose();
    await _pc?.close();
    _pc = null;
    _localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    state.value = CallState.ended;
  }

  Future<void> dispose() async {
    await _signalSub?.cancel();
    await _localStream?.dispose();
    await _pc?.close();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
