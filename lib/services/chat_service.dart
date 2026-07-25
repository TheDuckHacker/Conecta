import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
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
      throw Exception(e.message ?? 'Error al obtener mensajes');
    }
  }

  Future<List<Document>> getUserChats(String userId) async {
    try {
      final chats = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [
          Query.search('participants', userId),
          Query.orderDesc('lastMessageTime'),
        ],
      );
      return chats.documents;
    } on AppwriteException catch (e) {
      throw Exception(e.message ?? 'Error al obtener chats');
    }
  }

  Future<Document?> findExistingChat({
    required String participant1Id,
    required String participant2Id,
  }) async {
    try {
      final chats = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [
          Query.search('participants', participant1Id),
          Query.search('participants', participant2Id),
        ],
      );
      return chats.documents.isNotEmpty ? chats.documents.first : null;
    } on AppwriteException {
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
      throw Exception(e.message ?? 'Error al buscar usuarios');
    }
  }
}
