import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'chat_service.dart';

/// Sala de videollamada accesible: sincroniza subtítulos por Appwrite Realtime.
class CallService {
  final _chatService = ChatService();

  /// Prefijo interno para no mezclar con chats normales en la UI.
  static const captionPrefix = '⟦CAPTION⟧';

  Future<Document> createOrJoinRoom({
    required String currentUserId,
    required String otherUserId,
  }) async {
    return _chatService.resolveChat(
      userId: currentUserId,
      otherUserId: otherUserId,
    );
  }

  Future<void> sendCaption({
    required String roomId,
    required String senderId,
    required String text,
    required String role, // 'sign' | 'speech' | 'typed'
  }) async {
    final clean = text.trim();
    if (clean.isEmpty || roomId.isEmpty) return;
    try {
      await databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        documentId: ID.unique(),
        data: {
          'chatId': roomId,
          'senderId': senderId,
          'text': '$captionPrefix$role|$clean',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
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
        documentId: roomId,
        data: {
          'lastMessage': clean,
          'lastMessageTime': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } on AppwriteException catch (e) {
      debugPrint('sendCaption: ${e.message}');
    }
  }

  RealtimeSubscription subscribeCaptions(String roomId) {
    return realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.messagesCollectionId}.documents',
    ]);
  }

  static String? parseCaption(String raw) {
    if (!raw.startsWith(captionPrefix)) return null;
    final body = raw.substring(captionPrefix.length);
    final idx = body.indexOf('|');
    if (idx < 0) return body;
    return body.substring(idx + 1);
  }

  static String? parseCaptionRole(String raw) {
    if (!raw.startsWith(captionPrefix)) return null;
    final body = raw.substring(captionPrefix.length);
    final idx = body.indexOf('|');
    if (idx < 0) return null;
    return body.substring(0, idx);
  }
}
