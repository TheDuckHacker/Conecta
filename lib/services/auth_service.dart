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

  /// Email interno generado desde los dígitos del teléfono.
  /// Appwrite lo exige; el usuario nunca lo ve.
  String _emailFromPhone(String phone) => '${_digits(phone)}@conecta.app';

  /// Genera una contraseña determinista de al menos 16 caracteres
  /// usando solo caracteres alfanuméricos (sin $, +, etc.).
  String _passwordFromPhone(String phone) {
    final digits = _digits(phone);

    // Hash simple pero estable
    int h1 = 0x811c9dc5; // FNV offset basis
    for (int i = 0; i < digits.length; i++) {
      h1 = (h1 ^ digits.codeUnitAt(i)) & 0xFFFFFFFF;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
    }

    // Segundo hash con seed diferente para más entropía
    int h2 = 0;
    for (int i = 0; i < digits.length; i++) {
      h2 = ((h2 << 5) - h2 + digits.codeUnitAt(i)) & 0xFFFFFFFF;
    }

    final hex1 = h1.abs().toRadixString(16).padLeft(8, '0');
    final hex2 = h2.abs().toRadixString(16).padLeft(8, '0');

    // Resultado: "Cx" + 16 hex chars = 18 chars, siempre seguro para Appwrite
    return 'Cx$hex1$hex2';
  }

  /// Contraseña legacy para compatibilidad con cuentas antiguas.
  String _legacyPassword(String phone) {
    final digits = _digits(phone);
    int hash = 0;
    for (int i = 0; i < digits.length; i++) {
      hash = ((hash << 5) - hash + digits.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    final hex = hash.abs().toRadixString(16);
    return 'c\$${hex.padLeft(12, '0')}';
  }

  String _friendlyError(AppwriteException e, {required bool isRegister}) {
    final raw = (e.message ?? '').toLowerCase();
    final type = (e.type ?? '').toLowerCase();
    final code = e.code;

    debugPrint('Appwrite auth error [$code] type=$type msg=${e.message}');

    if (code == 409 ||
        raw.contains('already exists') ||
        type.contains('user_already_exists')) {
      return 'Este número ya está registrado. Inicia sesión.';
    }
    if (code == 401 ||
        type.contains('user_invalid_credentials') ||
        raw.contains('invalid credentials')) {
      return isRegister
          ? 'No se pudo crear la cuenta. Revisa tu número.'
          : 'Número no registrado o incorrecto. ¿Ya creaste tu cuenta?';
    }
    if (raw.contains('rate limit') || code == 429) {
      return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
    }
    if (raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('failed host lookup')) {
      return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
    }
    if (raw.contains('session') && raw.contains('prohibited')) {
      return 'Ya hay una sesión activa. Cierra la app e intenta de nuevo.';
    }
    if (raw.contains('password')) {
      return 'Error de autenticación. Intenta registrarte de nuevo.';
    }

    return isRegister
        ? 'No se pudo crear la cuenta. Intenta de nuevo.'
        : 'No se pudo iniciar sesión. Verifica tu número.';
  }

  Future<void> _clearExistingSession() async {
    try {
      await account.deleteSession(sessionId: 'current');
    } catch (_) {}
  }

  /// Intenta iniciar sesión con la contraseña nueva, si falla prueba la legacy.
  Future<Session> _tryLogin(String email, String phone) async {
    final passwords = [
      _passwordFromPhone(phone),
      _legacyPassword(phone),
    ];

    AppwriteException? lastError;

    for (final password in passwords) {
      try {
        debugPrint('Intentando login con email=$email password=${password.substring(0, 4)}...');
        return await account.createEmailPasswordSession(
          email: email,
          password: password,
        );
      } on AppwriteException catch (e) {
        lastError = e;
        debugPrint('Login fallido con variante: ${e.message}');
        continue;
      }
    }

    throw lastError ?? AppwriteException('Invalid credentials');
  }

  /// Crea cuenta + inicia sesión + guarda perfil.
  Future<User> register({
    required String name,
    required String phone,
  }) async {
    final digits = _digits(phone);
    final email = _emailFromPhone(digits);
    final password = _passwordFromPhone(digits);

    debugPrint('=== REGISTRO ===');
    debugPrint('Phone input: $phone');
    debugPrint('Digits: $digits');
    debugPrint('Email: $email');
    debugPrint('Password: ${password.substring(0, 4)}... (${password.length} chars)');

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
        // Ya existe → intentar login
        debugPrint('Cuenta ya existe, intentando login...');
        await _clearExistingSession();
        try {
          await _tryLogin(email, digits);
        } catch (_) {
          throw Exception('Este número ya está registrado. Usa Iniciar Sesión.');
        }

        final current = await getCurrentUser();
        if (current == null) {
          throw Exception('Este número ya está registrado. Inicia sesión.');
        }
        await ensureUserProfile(
          userId: current.$id,
          name: name,
          phone: normalizePhone(phone),
        );
        return current;
      }
      throw Exception(_friendlyError(e, isRegister: true));
    }

    // Crear sesión después de registrar
    try {
      await account.createEmailPasswordSession(email: email, password: password);
      debugPrint('Sesión creada exitosamente');
    } on AppwriteException catch (e) {
      debugPrint('Error creando sesión post-registro: ${e.message}');
      throw Exception(
        'Cuenta creada, pero no se pudo iniciar sesión. Prueba Iniciar Sesión con el mismo número.',
      );
    }

    await ensureUserProfile(
      userId: user.$id,
      name: name,
      phone: normalizePhone(phone),
    );

    return user;
  }

  /// Inicia sesión con un número de teléfono.
  Future<Session> login({required String phone}) async {
    final digits = _digits(phone);
    final email = _emailFromPhone(digits);

    debugPrint('=== LOGIN ===');
    debugPrint('Phone input: $phone');
    debugPrint('Digits: $digits');
    debugPrint('Email: $email');

    await _clearExistingSession();

    try {
      final session = await _tryLogin(email, digits);

      // Asegurar perfil si faltaba
      final user = await account.get();
      await ensureUserProfile(
        userId: user.$id,
        name: user.name.isNotEmpty ? user.name : 'Usuario',
        phone: normalizePhone(phone),
      );

      debugPrint('Login exitoso: ${user.$id}');
      return session;
    } on AppwriteException catch (e) {
      throw Exception(_friendlyError(e, isRegister: false));
    }
  }

  /// Crea el perfil en la DB si no existe; si ya existe, no falla.
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
      'phone': phone,
      'avatar': '',
      'status': 'online',
      'createdAt': DateTime.now().toIso8601String(),
    };

    // Guardar también en prefs del account (fallback)
    try {
      await account.updatePrefs(prefs: {
        'name': name,
        'phone': phone,
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
      // Reintento sin permissions explícitos
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
