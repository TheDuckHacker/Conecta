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

  /// Email interno (Appwrite exige email; el usuario nunca lo ve).
  String _emailFromPhone(String phone) => '${_digits(phone)}@conecta.app';

  /// Contraseña determinista y segura de 18 caracteres.
  String _passwordFromPhone(String phone) {
    final digits = _digits(phone);

    int h1 = 0x811c9dc5;
    for (int i = 0; i < digits.length; i++) {
      h1 = (h1 ^ digits.codeUnitAt(i)) & 0xFFFFFFFF;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
    }

    int h2 = 0;
    for (int i = 0; i < digits.length; i++) {
      h2 = ((h2 << 5) - h2 + digits.codeUnitAt(i)) & 0xFFFFFFFF;
    }

    final hex1 = h1.abs().toRadixString(16).padLeft(8, '0');
    final hex2 = h2.abs().toRadixString(16).padLeft(8, '0');

    return 'Cx$hex1$hex2';
  }

  /// Contraseña legacy alternativa por compatibilidad.
  String _legacyPassword(String phone) {
    final digits = _digits(phone);
    int hash = 0;
    for (int i = 0; i < digits.length; i++) {
      hash = ((hash << 5) - hash + digits.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    final hex = hash.abs().toRadixString(16);
    return 'c\$${hex.padLeft(12, '0')}';
  }

  Future<void> _clearExistingSession() async {
    try {
      await account.deleteSession(sessionId: 'current');
    } catch (_) {}
  }

  /// Inicia sesión directa usando solo el número de teléfono.
  Future<Session> login({required String phone}) async {
    final digits = _digits(phone);
    final email = _emailFromPhone(digits);
    final normalized = normalizePhone(phone);

    debugPrint('=== LOGIN DIRECTO POR TELÉFONO ===');
    debugPrint('Phone: $normalized, Email: $email');

    await _clearExistingSession();

    final passwords = [
      _passwordFromPhone(phone),
      _legacyPassword(phone),
    ];

    AppwriteException? lastError;

    for (final password in passwords) {
      try {
        final session = await account.createEmailPasswordSession(
          email: email,
          password: password,
        );

        final user = await account.get();
        await ensureUserProfile(
          userId: user.$id,
          name: user.name.isNotEmpty ? user.name : 'Usuario',
          phone: normalized,
        );

        debugPrint('Login exitoso: ${user.$id}');
        return session;
      } on AppwriteException catch (e) {
        lastError = e;
        continue;
      }
    }

    throw Exception(_friendlyError(lastError ?? AppwriteException('Invalid credentials'), isRegister: false));
  }

  /// Registra e inicia sesión directa usando nombre + teléfono.
  Future<User> register({
    required String name,
    required String phone,
  }) async {
    final digits = _digits(phone);
    final email = _emailFromPhone(digits);
    final password = _passwordFromPhone(digits);
    final normalized = normalizePhone(phone);

    debugPrint('=== REGISTRO DIRECTO POR TELÉFONO ===');
    debugPrint('Name: $name, Phone: $normalized, Email: $email');

    await _clearExistingSession();

    late User user;

    try {
      user = await account.create(
        userId: ID.unique(),
        name: name,
        email: email,
        password: password,
      );
      debugPrint('Cuenta creada: ${user.$id}');
    } on AppwriteException catch (e) {
      if (e.code == 409 ||
          (e.message ?? '').toLowerCase().contains('already exists')) {
        // Si la cuenta ya existe, iniciamos sesión directamente
        debugPrint('El usuario ya existe, iniciando sesión automáticamente...');
        await login(phone: normalized);
        final current = await getCurrentUser();
        if (current != null) {
          await ensureUserProfile(
            userId: current.$id,
            name: name,
            phone: normalized,
          );
          return current;
        }
      }
      throw Exception(_friendlyError(e, isRegister: true));
    }

    // Iniciar sesión inmediatamente tras registrar
    try {
      await account.createEmailPasswordSession(email: email, password: password);
    } on AppwriteException catch (e) {
      debugPrint('Error en sesión post-registro: ${e.message}');
    }

    await ensureUserProfile(
      userId: user.$id,
      name: name,
      phone: normalized,
    );

    return user;
  }

  /// Crea/asegura el perfil del usuario en la base de datos.
  Future<void> ensureUserProfile({
    required String userId,
    required String name,
    required String phone,
  }) async {
    final normalizedPhone = normalizePhone(phone);

    try {
      final doc = await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
      );

      final existingName = (doc.data['name'] ?? '').toString();
      final existingPhone = (doc.data['phone'] ?? '').toString();

      // Si el nombre guardado es 'Usuario' o está vacío y tenemos un nombre válido, actualizarlo
      if ((existingName.isEmpty || existingName == 'Usuario') &&
          name.isNotEmpty &&
          name != 'Usuario') {
        await databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: userId,
          data: {
            'name': name,
            if (existingPhone.isEmpty) 'phone': normalizedPhone,
          },
        );
      }
      return;
    } on AppwriteException {
      // No existe el documento de usuario, se procede a crear
    }

    final data = {
      'name': name.isNotEmpty ? name : 'Usuario',
      'phone': normalizedPhone,
      'avatar': '',
      'status': 'online',
      'createdAt': DateTime.now().toIso8601String(),
    };

    try {
      // IMPORTANTE: fusionar prefs para no borrar contactIds
      final current = await account.get();
      final prefs = Map<String, dynamic>.from(current.prefs.data);
      prefs['name'] = name;
      prefs['phone'] = normalizedPhone;
      await account.updatePrefs(prefs: prefs);
      if (name.isNotEmpty && name != 'Usuario') {
        await account.updateName(name: name);
      }
    } catch (e) {
      debugPrint('Error actualizando prefs: $e');
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

  String _friendlyError(AppwriteException e, {required bool isRegister}) {
    final raw = (e.message ?? '').toLowerCase();
    final code = e.code;

    if (code == 409 || raw.contains('already exists')) {
      return 'Este número ya está registrado. Inicia sesión.';
    }
    if (code == 401 || raw.contains('invalid credentials')) {
      return isRegister
          ? 'No se pudo crear la cuenta. Verifica tu número.'
          : 'Número no registrado. ¡Regístrate primero!';
    }
    if (raw.contains('network') || raw.contains('socket') || raw.contains('failed host lookup')) {
      return 'Sin conexión a internet. Revisa tu red.';
    }
    return 'Error (${e.code}): ${e.message ?? 'Intenta de nuevo.'}';
  }

  Future<User?> getCurrentUser() async {
    try {
      return await account.get();
    } on AppwriteException {
      return null;
    }
  }

  /// Convención de `users.status`:
  /// - online / offline
  /// - typing:<chatId>  → escribiendo en ese chat (sigue contando como en línea)
  static bool isOnlineStatus(String status) =>
      status == 'online' || status.startsWith('typing:');

  static bool isTypingInChat(String status, String chatId) =>
      chatId.isNotEmpty && status == 'typing:$chatId';

  Future<void> setOnlineStatus(String userId, bool isOnline) async {
    try {
      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
        data: {'status': isOnline ? 'online' : 'offline'},
      );
    } on AppwriteException {
      // Silently fail
    }
  }

  /// Marca que el usuario está escribiendo en un chat (1 update liviano).
  Future<void> setTypingStatus(String userId, String chatId) async {
    if (userId.isEmpty || chatId.isEmpty) return;
    try {
      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
        data: {'status': 'typing:$chatId'},
      );
    } on AppwriteException catch (e) {
      debugPrint('setTypingStatus: ${e.message}');
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
