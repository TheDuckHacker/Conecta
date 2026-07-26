import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/avatar_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _avatarService = AvatarService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _avatarController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _picking = false;
  String _currentUserId = '';
  String _currentStatus = 'offline';
  String _localPath = '';

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
        _localPath =
            (await _avatarService.localPathFor(user.$id)) ?? '';
        if (profile != null) {
          _nameController.text = profile['name'] ?? '';
          _phoneController.text =
              (profile['phone'] ?? '').toString().replaceFirst('+', '');
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
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_picking || _currentUserId.isEmpty) return;
    setState(() => _picking = true);
    try {
      final result = await _avatarService.pickAndUpload(
        userId: _currentUserId,
        source: source,
      );
      if (result == null) return;
      final local = await _avatarService.localPathFor(_currentUserId);
      if (!mounted) return;
      setState(() {
        if (AvatarService.isNetworkAvatar(result)) {
          _avatarController.text = result;
        }
        _localPath = local ?? result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto de perfil actualizada'),
          backgroundColor: Color(0xff2ECC71),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo subir la foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Elegir de galería'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Tomar foto'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Pegar URL'),
              onTap: () {
                Navigator.pop(ctx);
                _showUrlDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showUrlDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('URL de imagen'),
        content: TextField(
          controller: _avatarController,
          decoration: const InputDecoration(
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('Usar'),
          ),
        ],
      ),
    );
  }

  ImageProvider? _imageProvider() {
    final url = _avatarController.text.trim();
    if (AvatarService.isNetworkAvatar(url)) return NetworkImage(url);
    if (_localPath.isNotEmpty && File(_localPath).existsSync()) {
      return FileImage(File(_localPath));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final img = _imageProvider();
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
          'Mi Perfil',
          style: TextStyle(
            color: Color(0xff121B35),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Guardar',
                    style: TextStyle(
                      color: Color(0xff37C8F2),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xff37C8F2)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: const Color(0xffCDEFF7),
                          backgroundImage: img,
                          onBackgroundImageError:
                              img != null ? (_, __) {} : null,
                          child: _picking
                              ? const CircularProgressIndicator()
                              : (img == null
                                  ? Text(
                                      _nameController.text.isNotEmpty
                                          ? _nameController.text[0]
                                              .toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 45,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xff121B35),
                                      ),
                                    )
                                  : null),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Material(
                            color: const Color(0xff37C8F2),
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 20),
                              onPressed: _showAvatarOptions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Toca la cámara para galería o foto',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 30),
                  _field('Nombre', _nameController, Icons.person_outline),
                  const SizedBox(height: 14),
                  _field(
                    'Teléfono',
                    _phoneController,
                    Icons.phone_outlined,
                    enabled: false,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      AuthService.isOnlineStatus(_currentStatus)
                          ? 'Estado: En línea'
                          : 'Estado: Desconectado',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c,
    IconData icon, {
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: c,
        enabled: enabled,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xff37C8F2)),
          labelText: label,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }
}
