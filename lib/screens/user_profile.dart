import 'package:flutter/material.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/screens/chat_detail.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String currentUserId;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.currentUserId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _authService = AuthService();
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      _profile = await _authService.getUserProfile(widget.userId);
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?['name'] ?? 'Usuario';
    final phone = _profile?['phone'] ?? '';
    final avatar = _profile?['avatar'] ?? '';
    final status = _profile?['status'] ?? 'offline';

    return Scaffold(
      backgroundColor: const Color(0xffF5F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xff121B35)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Perfil",
          style: TextStyle(color: Color(0xff121B35), fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xff37C8F2)))
          : _profile == null
              ? const Center(child: Text("Usuario no encontrado", style: TextStyle(color: Colors.grey)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Avatar con estado
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 65,
                            backgroundColor: const Color(0xffCDEFF7),
                            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                            onBackgroundImageError: avatar.isNotEmpty ? (_, __) {} : null,
                            child: avatar.isEmpty
                                ? Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 50,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xff121B35),
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: status == 'online' ? const Color(0xff2ECC71) : Colors.grey,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Nombre
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff121B35),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Estado
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: status == 'online'
                              ? const Color(0xff2ECC71).withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status == 'online' ? 'En línea' : 'Último visto reciente',
                          style: TextStyle(
                            color: status == 'online' ? const Color(0xff2ECC71) : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      // Info cards
                      _buildInfoCard(Icons.phone_outlined, "Teléfono", phone.isNotEmpty ? phone : "No disponible"),
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        Icons.info_outline,
                        "Acerca de",
                        "Usuario de Conecta LSB",
                      ),
                      const SizedBox(height: 30),
                      // Botón chatear
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(
                                  chatId: '',
                                  name: name,
                                  avatar: avatar,
                                  isActive: status == 'online',
                                  currentUserId: widget.currentUserId,
                                  otherUserId: widget.userId,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                          label: const Text(
                            "Enviar mensaje",
                            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff37C8F2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xff37C8F2).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xff37C8F2)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xffA8B8C0), fontSize: 13)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xff121B35), fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
