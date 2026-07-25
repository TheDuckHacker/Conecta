import 'dart:async';
import 'package:flutter/material.dart';

class VideoCallScreen extends StatefulWidget {
  final String userName;
  final String userAvatar;
  final bool isVideoCall;

  const VideoCallScreen({
    super.key,
    required this.userName,
    required this.userAvatar,
    this.isVideoCall = true,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isFrontCamera = true;
  bool _isConnected = false;
  int _callDurationSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Simular conexión a los 2 segundos
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isConnected = true;
        });
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.userName.isNotEmpty ? widget.userName : 'Contacto';

    return Scaffold(
      backgroundColor: const Color(0xff0F172A),
      body: Stack(
        children: [
          // 1. Fondo de video remoto
          Positioned.fill(
            child: _isConnected && widget.isVideoCall && !_isVideoOff
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff1E293B), Color(0xff0F172A)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 65,
                          backgroundColor: const Color(0xff37C8F2).withValues(alpha: 0.2),
                          backgroundImage: widget.userAvatar.isNotEmpty
                              ? NetworkImage(widget.userAvatar)
                              : null,
                          child: widget.userAvatar.isEmpty
                              ? Text(
                                  name[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xff37C8F2),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_rounded,
                                  color: Color(0xff37C8F2), size: 18),
                              SizedBox(width: 8),
                              Text(
                                "Videollamada activa",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    color: const Color(0xff0F172A),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: const Color(0xff334155),
                            backgroundImage: widget.userAvatar.isNotEmpty
                                ? NetworkImage(widget.userAvatar)
                                : null,
                            child: widget.userAvatar.isEmpty
                                ? Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // 2. Previsualización de cámara propia (Esquina superior derecha)
          if (widget.isVideoCall && !_isVideoOff)
            Positioned(
              top: 50,
              right: 20,
              child: Container(
                width: 110,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xff37C8F2).withValues(alpha: 0.6), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Container(
                        color: const Color(0xff1E293B),
                        child: const Center(
                          child: Icon(Icons.person,
                              color: Colors.white54, size: 40),
                        ),
                      ),
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "Tú",
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Encabezado con Nombre y Duración
          Positioned(
            top: 50,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isConnected
                      ? _formatDuration(_callDurationSeconds)
                      : (widget.isVideoCall
                          ? 'Iniciando videollamada...'
                          : 'Llamando...'),
                  style: TextStyle(
                    color: _isConnected
                        ? const Color(0xff37C8F2)
                        : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // 4. Barra de Controles Inferior
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Mute Mic
                _buildControlButton(
                  icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: _isMuted ? Colors.white : Colors.white24,
                  iconColor: _isMuted ? Colors.black : Colors.white,
                  onTap: () => setState(() => _isMuted = !_isMuted),
                ),

                // Toggle Video
                if (widget.isVideoCall)
                  _buildControlButton(
                    icon: _isVideoOff
                        ? Icons.videocam_off_rounded
                        : Icons.videocam_rounded,
                    color: _isVideoOff ? Colors.white : Colors.white24,
                    iconColor: _isVideoOff ? Colors.black : Colors.white,
                    onTap: () => setState(() => _isVideoOff = !_isVideoOff),
                  ),

                // Switch Camera
                if (widget.isVideoCall)
                  _buildControlButton(
                    icon: Icons.cameraswitch_rounded,
                    color: Colors.white24,
                    iconColor: Colors.white,
                    onTap: () =>
                        setState(() => _isFrontCamera = !_isFrontCamera),
                  ),

                // End Call
                _buildControlButton(
                  icon: Icons.call_end_rounded,
                  color: Colors.redAccent,
                  iconColor: Colors.white,
                  size: 64,
                  iconSize: 30,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
    double size = 52,
    double iconSize = 24,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}
