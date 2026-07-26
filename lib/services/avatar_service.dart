import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_config.dart';
import 'auth_service.dart';

/// Sube o elige foto de perfil (galería / cámara).
class AvatarService {
  final _picker = ImagePicker();
  final _auth = AuthService();

  Future<String?> pickAndUpload({
    required String userId,
    required ImageSource source,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return null;

    // Copia local (siempre disponible en este dispositivo)
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/avatar_$userId.jpg';
    await File(picked.path).copy(localPath);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_avatar_$userId', localPath);

    // Intentar Appwrite Storage (compartible con otros usuarios)
    try {
      final storage = Storage(appwriteClient);
      final fileId = ID.unique();
      await storage.createFile(
        bucketId: AppwriteConfig.avatarsBucketId,
        fileId: fileId,
        file: InputFile.fromPath(path: localPath, filename: 'avatar.jpg'),
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.any()),
          Permission.delete(Role.any()),
        ],
      );
      final url =
          '${AppwriteConfig.endpoint}/storage/buckets/${AppwriteConfig.avatarsBucketId}/files/$fileId/view?project=${AppwriteConfig.projectId}';
      await _auth.updateProfile(userId: userId, avatar: url);
      return url;
    } catch (e) {
      debugPrint('Avatar upload Storage: $e — usando ruta local');
      // Guardar marcador local; otros verán inicial hasta que haya bucket
      await _auth.updateProfile(
        userId: userId,
        avatar: 'local://avatar_$userId',
      );
      return localPath;
    }
  }

  Future<String?> localPathFor(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('local_avatar_$userId');
  }

  /// Resuelve imagen para UI (red o archivo local).
  static bool isNetworkAvatar(String avatar) =>
      avatar.startsWith('http://') || avatar.startsWith('https://');
}
