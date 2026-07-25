import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'chat_service.dart';

class ContactService {
  final _chatService = ChatService();

  /// Buscar un usuario por número de teléfono.
  Future<Document?> searchUserByPhone(String phone) async {
    try {
      final normalized = '+${phone.replaceAll(RegExp(r'[^0-9]'), '')}';

      final result = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [
          Query.equal('phone', normalized),
          Query.limit(1),
        ],
      );

      if (result.documents.isNotEmpty) {
        return result.documents.first;
      }

      // Intentar búsqueda por dígitos
      final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final result2 = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [
          Query.search('phone', digitsOnly),
          Query.limit(5),
        ],
      );

      if (result2.documents.isNotEmpty) {
        return result2.documents.first;
      }

      return null;
    } on AppwriteException catch (e) {
      debugPrint('Error buscando usuario: ${e.message}');
      return null;
    }
  }

  /// Agregar un contacto. Si la colección 'contacts' no existe en Appwrite,
  /// crea automáticamente el chat en la colección 'chats' como fallback.
  Future<Document> addContact({
    required String userId,
    required String contactUserId,
    required String phone,
  }) async {
    try {
      final existing = await _findContact(userId, contactUserId);
      if (existing != null) {
        throw Exception('Este contacto ya está agregado.');
      }

      final doc = await databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.contactsCollectionId,
        documentId: ID.unique(),
        data: {
          'userId': userId,
          'contactUserId': contactUserId,
          'phone': phone,
          'createdAt': DateTime.now().toIso8601String(),
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.any()),
          Permission.delete(Role.any()),
        ],
      );
      return doc;
    } on AppwriteException catch (e) {
      debugPrint('Appwrite exception en addContact: [${e.code}] ${e.message}');

      // Si la colección 'contacts' no existe en Appwrite (error 404)
      if (e.code == 404 || (e.message ?? '').contains('could not be found')) {
        debugPrint('Fallback: creando chat directo en la colección chats...');
        // Crear o buscar chat existente en la colección 'chats'
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

      throw Exception('No se pudo agregar el contacto. ${e.message}');
    }
  }

  /// Eliminar un contacto.
  Future<void> removeContact(String documentId) async {
    try {
      await databases.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.contactsCollectionId,
        documentId: documentId,
      );
    } on AppwriteException catch (e) {
      debugPrint('Error eliminando contacto: ${e.message}');
    }
  }

  /// Obtener todos los contactos de un usuario.
  /// Si la colección 'contacts' no existe, obtiene los participantes de chats como contactos.
  Future<List<Document>> getContacts(String userId) async {
    try {
      final result = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.contactsCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.orderDesc('createdAt'),
          Query.limit(100),
        ],
      );
      return result.documents;
    } on AppwriteException catch (e) {
      debugPrint('Contacts collection fallback: ${e.message}');

      // Fallback: extraer contactos a partir de los chats activos
      try {
        final userChats = await _chatService.getUserChats(userId);
        final List<Document> chatContacts = [];
        for (final chat in userChats) {
          final participants = List<String>.from(chat.data['participants'] ?? []);
          final otherId = participants.firstWhere((id) => id != userId, orElse: () => '');
          if (otherId.isNotEmpty) {
            chatContacts.add(Document(
              $id: chat.$id,
              $collectionId: AppwriteConfig.contactsCollectionId,
              $databaseId: AppwriteConfig.databaseId,
              $createdAt: chat.$createdAt,
              $updatedAt: chat.$updatedAt,
              $permissions: [],
              data: {
                'userId': userId,
                'contactUserId': otherId,
                'phone': '',
              },
            ));
          }
        }
        return chatContacts;
      } catch (_) {
        return [];
      }
    }
  }

  /// Verificar si un contacto ya existe.
  Future<Document?> _findContact(String userId, String contactUserId) async {
    try {
      final result = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.contactsCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('contactUserId', contactUserId),
          Query.limit(1),
        ],
      );
      return result.documents.isNotEmpty ? result.documents.first : null;
    } on AppwriteException {
      return null;
    }
  }

  /// Obtener la info de un usuario por su ID.
  Future<Document?> getUserById(String userId) async {
    try {
      return await databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        documentId: userId,
      );
    } on AppwriteException {
      return null;
    }
  }
}
