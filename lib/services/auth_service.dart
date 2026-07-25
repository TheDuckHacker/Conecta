import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';

class AuthService {
  /// Normaliza el teléfono a formato E.164: +5917xxxxxxx
  String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '+$digits';
  }

  String _digits(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

  /// Email interno (Appwrite lo exige; el usuario nunca lo ve).
  String _emailFromPhone(String phone) => '${_digits(phone)}@conecta.app';

  String _hash(String value, {bool pad = true}) {
    int hash = 0;
    for (int i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash + value.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    final hex = hash.abs().toRadixString(16);
    return 'c\$${pad ? hex.padLeft(12, '0') : hex}';
  }

  /// Contraseña actual (estable).
  String _passwordFromPhone(String phone) => _hash(_digits(phone), pad: true);

  /// Variantes antiguas para no romper cuentas ya creadas.
  List<({String email, String password})> _credentialVariants(String phone) {
    final normalized = normalizePhone(phone);
    final digits = _digits(phone);
    final email = _emailFromPhone(phone);
    final legacyEmail = '$normalized@conecta.app';

    return [
      (email: email, password: _passwordFromPhone(phone)),
      (email: email, password: _hash(digits, pad: false)),
      (email: email, password: _hash(normalized, pad: true)),
      (email: email, password: _hash(normalized, pad: false)),
      (email: legacyEmail, password: _hash(normalized, pad: false)),
      (email: legacyEmail, password: _hash(normalized, pad: true)),
      (email: legacyEmail, password: _hash(digits, pad: false)),
      (email: legacyEmail, password: _hash(digits, pad: true)),
    ];
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
    if (code == 401 && (raw.contains('permission') || type.contains('unauthorized'))) {
      return 'Sin permisos en Appwrite. Revisa la colección users.';
    }
    if (raw.contains('rate limit') || code == 429) {
      return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
    }
    if (raw.contains('network') || raw.contains('socket') || raw.contains('failed host lookup')) {
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

  /// Crea cuenta + inicia sesión + guarda perfil (orden correcto).
  Future<User> register({
    required String name,
    required String phone,
  }) async {
    final normalized = normalizePhone(phone);
    final email = _emailFromPhone(normalized);
    final password = _passwordFromPhone(normalized);

    await _clearExistingSession();

    late User user;

    try {
      user = await account.create(
        userId: ID.unique(),
        name: name,
        email: email,
        password: password,
      );
    } on AppwriteException catch (e) {
      // Si ya existe, intentamos iniciar sesión con ese número
      if (e.code == 409 ||
          (e.message ?? '').toLowerCase().contains('already exists')) {
        await login(phone: normalized);
        final current = await getCurrentUser();
        if (current == null) {
          throw Exception('Este número ya está registrado. Inicia sesión.');
        }
        await ensureUserProfile(
          userId: current.$id,
          name: name,
          phone: normalized,
        );
        return current;
      }
      throw Exception(_friendlyError(e, isRegister: true));
    }

    // IMPORTANTE: primero sesión, luego documento en la DB
    try {
      await account.createEmailPasswordSession(email: email, password: password);
    } on AppwriteException {
      throw Exception(
        'Cuenta creada, pero no se pudo iniciar sesión. Prueba Iniciar Sesión con el mismo número.',
      );
    }

    await ensureUserProfile(
      userId: user.$id,
      name: name,
      phone: normalized,
    );

    return user;
  }

  Future<Session> login({required String phone}) async {
    final normalized = normalizePhone(phone);
    await _clearExistingSession();

    AppwriteException? lastError;

    for (final creds in _credentialVariants(normalized)) {
      try {
        final session = await account.createEmailPasswordSession(
          email: creds.email,
          password: creds.password,
        );

        // Asegurar perfil si faltaba (registro a medias)
        final user = await account.get();
        await ensureUserProfile(
          userId: user.$id,
          name: user.name.isNotEmpty ? user.name : 'Usuario',
          phone: normalized,
        );

        return session;
      } on AppwriteException catch (e) {
        lastError = e;
        // Probar siguiente variante de credenciales
        continue;
      }
    }

    throw Exception(
      _friendlyError(
        lastError ?? AppwriteException('Invalid credentials'),
        isRegister: false,
      ),
    );
  }

  /// Crea el perfil si no existe; si ya existe, no falla.
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

    // Guardar también en prefs del account (fallback si la DB no tiene permisos)
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
      // Reintento sin permissions explícitos (usa defaults de la colección)
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
        // No bloquear login/registro: la sesión ya existe
      }
    }
  }

  @Deprecated('Usa register()')
  Future<User> createAccount({
    required String name,
    required String phone,
  }) =>
      register(name: name, phone: phone);

  @Deprecated('Usa ensureUserProfile()')
  Future<void> saveUserProfile({
    required String userId,
    required String name,
    required String phone,
  }) =>
      ensureUserProfile(userId: userId, name: name, phone: phone);

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
