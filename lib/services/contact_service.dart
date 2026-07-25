import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'chat_service.dart';

/// Contactos guardados en prefs de la cuenta (`contactIds`).
/// Solo aparecen los que el usuario agregó explícitamente.
class ContactService {
  final _chatService = ChatService();
  final Map<String, Document?> _userCache = {};

  static const _prefsKey = 'contactIds';

  Future<List<String>> _getContactIds() async {
    try {
      final user = await account.get();
      final raw = user.prefs.data[_prefsKey];
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
      return raw
          .toString()
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('getContactIds: $e');
      return [];
    }
  }

  Future<void> _saveContactIds(List<String> ids) async {
    final unique = ids.toSet().toList();
    try {
      // Conservar otras prefs
      final user = await account.get();
      final prefs = Map<String, dynamic>.from(user.prefs.data);
      prefs[_prefsKey] = unique.join(',');
      await account.updatePrefs(prefs: prefs);
    } on AppwriteException catch (e) {
      debugPrint('saveContactIds: ${e.message}');
      throw Exception('No se pudo guardar el contacto');
    }
  }

  /// Buscar un usuario por número de teléfono.
  Future<Document?> searchUserByPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = '+$digits';

    try {
      final result = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [
          Query.equal('phone', normalized),
          Query.limit(1),
        ],
      );
      if (result.documents.isNotEmpty) return result.documents.first;
    } on AppwriteException catch (e) {
      debugPrint('searchUserByPhone equal: ${e.message}');
    }

    try {
      final all = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [Query.limit(100)],
      );
      for (final doc in all.documents) {
        final p = (doc.data['phone'] ?? '')
            .toString()
            .replaceAll(RegExp(r'[^0-9]'), '');
        if (p == digits || p.endsWith(digits) || digits.endsWith(p)) {
          return doc;
        }
      }
    } on AppwriteException catch (e) {
      debugPrint('searchUserByPhone fallback: ${e.message}');
    }
    return null;
  }

  /// Agregar contacto: guardar ID + crear/abrir chat 1:1.
  Future<Document> addContact({
    required String userId,
    required String contactUserId,
    required String phone,
  }) async {
    if (userId == contactUserId) {
      throw Exception('No puedes agregarte a ti mismo.');
    }

    final ids = await _getContactIds();
    if (!ids.contains(contactUserId)) {
      ids.add(contactUserId);
      await _saveContactIds(ids);
    }

    Document? chat = await _chatService.findExistingChat(
      participant1Id: userId,
      participant2Id: contactUserId,
    );
    chat ??= await _chatService.createChat(
      participant1Id: userId,
      participant2Id: contactUserId,
    );
    return chat;
  }

  /// Quitar de la lista de contactos (el chat se mantiene).
  Future<void> removeContact(String contactUserId) async {
    final ids = await _getContactIds();
    ids.removeWhere((id) => id == contactUserId);
    await _saveContactIds(ids);
  }

  Future<bool> isContact(String contactUserId) async {
    final ids = await _getContactIds();
    return ids.contains(contactUserId);
  }

  /// Solo contactos que el usuario agregó.
  Future<List<Document>> getContacts(String userId) async {
    final ids = await _getContactIds();
    if (ids.isEmpty) return [];

    final List<Document> contacts = [];
    for (final id in ids) {
      if (id == userId) continue;
      final user = await getUserById(id);
      if (user != null) contacts.add(user);
    }
    return contacts;
  }

  Future<Document?> getUserById(String userId) async {
    if (userId.isEmpty) return null;
    if (_userCache.containsKey(userId)) return _userCache[userId];

    try {
      final doc = await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
      );
      _userCache[userId] = doc;
      return doc;
    } on AppwriteException catch (e) {
      debugPrint('getUserById($userId): ${e.message}');
      _userCache[userId] = null;
      return null;
    }
  }

  void clearCache() => _userCache.clear();
}
