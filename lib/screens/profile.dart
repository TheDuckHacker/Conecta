import 'package:flutter/material.dart';
import 'package:conecta_lsb/services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _avatarController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String _currentUserId = '';
  String _currentStatus = 'offline';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        _currentUserId = user.$id;
        final profile = await _authService.getUserProfile(user.$id);
        if (profile != null) {
          _nameController.text = profile['name'] ?? '';
          _phoneController.text = (profile['phone'] ?? '').replaceFirst('+', '');
          _avatarController.text = profile['avatar'] ?? '';
          _currentStatus = profile['status'] ?? 'offline';
        } else {
          _nameController.text = user.name;
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);

    try {
      await _authService.updateProfile(
        userId: _currentUserId,
        name: _nameController.text.trim(),
        avatar: _avatarController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado'),
            backgroundColor: Color(0xff2ECC71),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          "Mi Perfil",
          style: TextStyle(color: Color(0xff121B35), fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Guardar", style: TextStyle(color: Color(0xff37C8F2), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xff37C8F2)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildAvatarSection(),
                  const SizedBox(height: 30),
                  _buildField("Nombre", _nameController, Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildField("Teléfono", _phoneController, Icons.phone_outlined, enabled: false),
                  const SizedBox(height: 16),
                  _buildField("URL Foto de Perfil", _avatarController, Icons.image_outlined),
                  const SizedBox(height: 12),
                  if (_avatarController.text.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        _avatarController.text,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 120,
                          height: 120,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                        ),
                      ),
                    ),
                  const SizedBox(height: 30),
                  _buildStatusInfo(),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatarSection() {
    final avatarUrl = _avatarController.text;
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: const Color(0xffCDEFF7),
            backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            onBackgroundImageError: avatarUrl.isNotEmpty ? (_, __) {} : null,
            child: avatarUrl.isEmpty
                ? Text(
                    _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: Color(0xff121B35)),
                  )
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xff37C8F2),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                onPressed: () {
                  _showAvatarDialog();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAvatarDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Foto de perfil"),
        content: TextField(
          controller: _avatarController,
          decoration: const InputDecoration(
            hintText: "Pega una URL de imagen",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text("Aceptar"),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, {bool enabled = true}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: TextStyle(fontSize: 16, color: enabled ? Colors.black : Colors.grey),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xff37C8F2)),
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xffA8B8C0)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildStatusInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
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
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _currentStatus == 'online' ? const Color(0xff2ECC71) : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _currentStatus == 'online' ? 'En línea' : 'Desconectado',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
