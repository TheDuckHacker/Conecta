import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';

class AuthService {
  /// Extrae solo dígitos del teléfono.
  String _digits(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

  /// Normaliza el teléfono a formato E.164: +<dígitos>
  String normalizePhone(String phone) {
    final digits = _digits(phone);
    return '+$digits';
  }

  Future<void> _clearExistingSession() async {
    try {
      await account.deleteSession(sessionId: 'current');
    } catch (_) {}
  }

  /// Paso 1: Enviar código OTP al número de teléfono.
  /// Retorna el userId que se necesita para verificar el código.
  Future<String> sendOTP({required String phone}) async {
    final normalized = normalizePhone(phone);
    debugPrint('=== ENVIAR OTP ===');
    debugPrint('Phone: $normalized');

    await _clearExistingSession();

    try {
      final token = await account.createPhoneToken(
        userId: ID.unique(),
        phone: normalized,
      );
      debugPrint('OTP enviado. UserId: ${token.userId}');
      return token.userId;
    } on AppwriteException catch (e) {
      debugPrint('Error enviando OTP: [${e.code}] ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Paso 2: Verificar el código OTP e iniciar sesión.
  Future<Session> verifyOTP({
    required String userId,
    required String otp,
  }) async {
    debugPrint('=== VERIFICAR OTP ===');
    debugPrint('UserId: $userId, OTP: $otp');

    try {
      final session = await account.createSession(
        userId: userId,
        secret: otp,
      );
      debugPrint('Sesión creada exitosamente');
      return session;
    } on AppwriteException catch (e) {
      debugPrint('Error verificando OTP: [${e.code}] ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Guarda/actualiza el nombre del usuario después del login.
  Future<void> updateUserName(String name) async {
    try {
      await account.updateName(name: name);
    } catch (e) {
      debugPrint('Error actualizando nombre: $e');
    }
  }

  /// Crea el perfil en la DB si no existe.
  Future<void> ensureUserProfile({
    required String userId,
    required String name,
    required String phone,
  }) async {
    try {
      await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
      );
      // Ya existe
      return;
    } on AppwriteException {
      // No existe → crear
    }

    final data = {
      'name': name,
      'phone': normalizePhone(phone),
      'avatar': '',
      'status': 'online',
      'createdAt': DateTime.now().toIso8601String(),
    };

    try {
      await account.updatePrefs(prefs: {
        'name': name,
        'phone': normalizePhone(phone),
      });
      await account.updateName(name: name);
    } catch (e) {
      debugPrint('prefs update: $e');
    }

    try {
      await databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
        data: data,
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.any()),
          Permission.delete(Role.any()),
        ],
      );
    } on AppwriteException catch (e) {
      if (e.code == 409) return;
      try {
        await databases.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: userId,
          data: data,
        );
      } on AppwriteException catch (e2) {
        if (e2.code == 409) return;
        debugPrint('ensureUserProfile error: ${e2.message}');
      }
    }
  }

  String _friendlyError(AppwriteException e) {
    final raw = (e.message ?? '').toLowerCase();
    final code = e.code;

    debugPrint('Appwrite error [$code] msg=${e.message}');

    if (raw.contains('rate limit') || code == 429) {
      return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
    }
    if (raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('failed host lookup')) {
      return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
    }
    if (raw.contains('invalid token') ||
        raw.contains('invalid credentials') ||
        code == 401) {
      return 'Código incorrecto. Revisa e intenta de nuevo.';
    }
    if (raw.contains('expired')) {
      return 'El código expiró. Solicita uno nuevo.';
    }
    if (raw.contains('phone') && raw.contains('invalid')) {
      return 'Número de teléfono inválido. Verifica el formato.';
    }

    return 'Error: ${e.message ?? 'Intenta de nuevo.'}';
  }

  Future<User?> getCurrentUser() async {
    try {
      return await account.get();
    } on AppwriteException {
      return null;
    }
  }

  Future<void> setOnlineStatus(String userId, bool isOnline) async {
    try {
      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
        data: {
          'status': isOnline ? 'online' : 'offline',
        },
      );
    } on AppwriteException {
      // Silently fail
    }
  }

  Future<void> updateProfile({
    required String userId,
    String? name,
    String? phone,
    String? avatar,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (phone != null) data['phone'] = phone;
      if (avatar != null) data['avatar'] = avatar;

      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
        data: data,
      );
    } on AppwriteException {
      throw Exception('No se pudo actualizar el perfil');
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
      );
      return doc.data;
    } on AppwriteException {
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await account.deleteSession(sessionId: 'current');
    } on AppwriteException {
      throw Exception('No se pudo cerrar sesión');
    }
  }
}
