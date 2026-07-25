import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'chat_service.dart';

/// Contactos guardados en prefs de la cuenta (`contactIds`).
/// Se recuperan también desde chats existentes (por si las prefs se borraron).
class ContactService {
  final _chatService = ChatService();
  final Map<String, Document?> _userCache = {};

  static const _prefsKey = 'contactIds';
  static const _removedKey = 'removedContactIds';

  List<String> _parseIds(dynamic raw) {
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
  }

  Future<Map<String, dynamic>> _prefsMap() async {
    final user = await account.get();
    return Map<String, dynamic>.from(user.prefs.data);
  }

  Future<List<String>> _getContactIds() async {
    try {
      final prefs = await _prefsMap();
      return _parseIds(prefs[_prefsKey]);
    } catch (e) {
      debugPrint('getContactIds: $e');
      return [];
    }
  }

  Future<List<String>> _getRemovedIds() async {
    try {
      final prefs = await _prefsMap();
      return _parseIds(prefs[_removedKey]);
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePrefsIds({
    List<String>? contactIds,
    List<String>? removedIds,
  }) async {
    try {
      final prefs = await _prefsMap();
      if (contactIds != null) {
        prefs[_prefsKey] = contactIds.toSet().toList().join(',');
      }
      if (removedIds != null) {
        prefs[_removedKey] = removedIds.toSet().toList().join(',');
      }
      await account.updatePrefs(prefs: prefs);
    } on AppwriteException catch (e) {
      debugPrint('savePrefsIds: ${e.message}');
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
    final removed = await _getRemovedIds();
    if (!ids.contains(contactUserId)) {
      ids.add(contactUserId);
    }
    removed.removeWhere((id) => id == contactUserId);
    await _savePrefsIds(contactIds: ids, removedIds: removed);

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
    final removed = await _getRemovedIds();
    ids.removeWhere((id) => id == contactUserId);
    if (!removed.contains(contactUserId)) {
      removed.add(contactUserId);
    }
    await _savePrefsIds(contactIds: ids, removedIds: removed);
  }

  Future<bool> isContact(String contactUserId) async {
    final ids = await _getContactIds();
    return ids.contains(contactUserId);
  }

  /// Contactos del usuario.
  ///
  /// Une prefs + personas con chat (recupera contactos perdidos).
  /// Respeta los que el usuario eliminó a propósito.
  Future<List<Document>> getContacts(String userId) async {
    final ids = await _syncContactIdsFromChats(userId);
    if (ids.isEmpty) return [];

    final List<Document> contacts = [];
    for (final id in ids) {
      if (id == userId) continue;
      final user = await getUserById(id);
      if (user != null) contacts.add(user);
    }
    return contacts;
  }

  Future<List<String>> _syncContactIdsFromChats(String userId) async {
    final saved = await _getContactIds();
    final removed = (await _getRemovedIds()).toSet();
    final merged = <String>{...saved};

    try {
      final chats = await _chatService.getUserChats(userId);
      for (final chat in chats) {
        final other = ChatService.otherParticipantId(chat, userId);
        if (other.isEmpty || other == userId) continue;
        if (removed.contains(other)) continue;
        merged.add(other);
      }
    } catch (e) {
      debugPrint('syncContactIdsFromChats: $e');
    }

    final list = merged.toList();
    if (list.length != saved.length || list.any((id) => !saved.contains(id))) {
      try {
        await _savePrefsIds(contactIds: list);
      } catch (e) {
        debugPrint('No se pudieron guardar contactos recuperados: $e');
      }
    }
    return list;
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
