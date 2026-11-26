import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_service.dart';

/// Full-screen call UI. Handles outgoing (calling), incoming (ringing -> accept/decline),
/// and connected states. Pops itself when the call ends.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.service,
    required this.title,
    this.incoming = false,
  });

  final CallService service;
  final String title;
  final bool incoming;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    widget.service.state.addListener(_onState);
  }

  void _onState() {
    if (widget.service.state.value == CallState.ended && mounted) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.service.state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final st = s.state.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video fills the screen.
          Positioned.fill(child: RTCVideoView(s.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
          // Local preview.
          Positioned(
            right: 16,
            top: 48,
            width: 110,
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RTCVideoView(s.localRenderer, mirror: true),
            ),
          ),
          // Status text.
          Positioned(
            top: 60,
            left: 24,
            child: Text(
              '${widget.title} • ${_label(st)}',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          // Controls.
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: widget.incoming && st == CallState.ringing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _btn(Icons.call_end, Colors.red, () async {
                          await s.hangup();
                        }),
                        _btn(Icons.call, Colors.green, () async {
                          await s.acceptIncoming();
                        }),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _btn(_muted ? Icons.mic_off : Icons.mic, Colors.white24, () async {
                          await s.toggleMute();
                          setState(() => _muted = !_muted);
                        }),
                        _btn(Icons.cameraswitch, Colors.white24, () => s.switchCamera()),
                        _btn(Icons.call_end, Colors.red, () async {
                          await s.hangup();
                        }),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _label(CallState s) => switch (s) {
        CallState.calling => 'Calling…',
        CallState.ringing => 'Incoming call',
        CallState.connected => 'Connected',
        CallState.ended => 'Ended',
        CallState.idle => '',
      };

  Widget _btn(IconData icon, Color color, VoidCallback onTap) => FloatingActionButton(
        heroTag: icon.codePoint,
        backgroundColor: color,
        onPressed: onTap,
        child: Icon(icon, color: Colors.white),
      );
}
