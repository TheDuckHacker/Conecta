import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';

class ContactService {
  /// Buscar un usuario por número de teléfono.
  Future<Document?> searchUserByPhone(String phone) async {
    try {
      // Normalizar: solo dígitos con +
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

      // Intentar búsqueda sin el + por si el formato difiere
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

  /// Agregar un contacto.
  Future<Document> addContact({
    required String userId,
    required String contactUserId,
    required String phone,
  }) async {
    try {
      // Verificar si ya existe
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
      debugPrint('Error agregando contacto: ${e.message}');
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
      throw Exception('No se pudo eliminar el contacto.');
    }
  }

  /// Obtener todos los contactos de un usuario.
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
      debugPrint('Error obteniendo contactos: ${e.message}');
      return [];
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
