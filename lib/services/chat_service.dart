import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';

class ChatService {
  Future<Document> createChat({
    required String participant1Id,
    required String participant2Id,
  }) async {
    try {
      final chat = await databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        documentId: ID.unique(),
        data: {
          'participants': [participant1Id, participant2Id],
          'lastMessage': '',
          'lastMessageTime': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.any()),
          Permission.delete(Role.any()),
        ],
      );
      return chat;
    } on AppwriteException catch (e) {
      throw Exception(e.message ?? 'Error al crear chat');
    }
  }

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    try {
      await databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        documentId: ID.unique(),
        data: {
          'chatId': chatId,
          'senderId': senderId,
          'text': text,
          'timestamp': DateTime.now().toIso8601String(),
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.any()),
          Permission.delete(Role.any()),
        ],
      );

      await databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        documentId: chatId,
        data: {
          'lastMessage': text,
          'lastMessageTime': DateTime.now().toIso8601String(),
        },
      );
    } on AppwriteException catch (e) {
      throw Exception(e.message ?? 'Error al enviar mensaje');
    }
  }

  Future<List<Document>> getMessages(String chatId) async {
    try {
      final messages = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.orderAsc('timestamp'),
          Query.limit(100),
        ],
      );
      return messages.documents;
    } on AppwriteException catch (e) {
      debugPrint('Error getMessages: ${e.message}');
      // Fallback sin queries
      try {
        final all = await databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.messagesCollectionId,
          queries: [Query.limit(100)],
        );
        final filtered = all.documents
            .where((m) => m.data['chatId'] == chatId)
            .toList();
        filtered.sort((a, b) => (a.data['timestamp'] ?? '')
            .toString()
            .compareTo((b.data['timestamp'] ?? '').toString()));
        return filtered;
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Document>> getUserChats(String userId) async {
    // 1. Intentar consulta directa por participantes
    try {
      final chats = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [
          Query.equal('participants', userId),
          Query.limit(100),
        ],
      );
      if (chats.documents.isNotEmpty) {
        return chats.documents;
      }
    } catch (_) {}

    try {
      final chats = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [
          Query.search('participants', userId),
          Query.limit(100),
        ],
      );
      if (chats.documents.isNotEmpty) {
        return chats.documents;
      }
    } catch (_) {}

    // 2. Fallback resiliente: Obtener lista de chats y filtrar en Dart
    try {
      final allChats = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [Query.limit(100)],
      );
      final userChats = allChats.documents.where((doc) {
        final parts = List<String>.from(doc.data['participants'] ?? []);
        return parts.contains(userId);
      }).toList();

      userChats.sort((a, b) => (b.data['lastMessageTime'] ?? '')
          .toString()
          .compareTo((a.data['lastMessageTime'] ?? '').toString()));

      return userChats;
    } on AppwriteException catch (e) {
      debugPrint('Error en getUserChats fallback: ${e.message}');
      return [];
    }
  }

  Future<Document?> findExistingChat({
    required String participant1Id,
    required String participant2Id,
  }) async {
    try {
      final userChats = await getUserChats(participant1Id);
      for (final chat in userChats) {
        final parts = List<String>.from(chat.data['participants'] ?? []);
        if (parts.contains(participant1Id) && parts.contains(participant2Id)) {
          return chat;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error en findExistingChat: $e');
      return null;
    }
  }

  Stream<RealtimeMessage> subscribeToMessages(String chatId) {
    final subscription = realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.messagesCollectionId}.documents',
    ]);

    return subscription.stream.where((event) {
      final payload = event.payload;
      return payload['chatId'] == chatId;
    });
  }

  Future<List<Document>> searchUsers(String query) async {
    try {
      final users = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [
          Query.search('name', query),
          Query.limit(20),
        ],
      );
      return users.documents;
    } on AppwriteException catch (e) {
      debugPrint('Error en searchUsers: ${e.message}');
      return [];
    }
  }
}
