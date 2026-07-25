import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';

class ChatService {
  static List<String> parseParticipants(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      return raw
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  static String otherParticipantId(Document chat, String currentUserId) {
    final parts = parseParticipants(chat.data['participants']);
    for (final id in parts) {
      if (id != currentUserId) return id;
    }
    return '';
  }

  /// Hora real del mensaje. Se prioriza `$createdAt` porque lo genera el
  /// servidor: el reloj de cada dispositivo puede estar desfasado y romper
  /// tanto el orden como las horas mostradas.
  static DateTime messageTime(Document message) {
    final server = DateTime.tryParse(message.$createdAt);
    if (server != null) return server.toLocal();
    final local = DateTime.tryParse((message.data['timestamp'] ?? '').toString());
    return local?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _pairKey(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<Document> createChat({
    required String participant1Id,
    required String participant2Id,
  }) async {
    if (participant1Id.isEmpty || participant2Id.isEmpty) {
      throw Exception('Participantes inválidos');
    }
    if (participant1Id == participant2Id) {
      throw Exception('No puedes crear un chat contigo mismo');
    }

    // Evitar duplicados
    final existing = await findExistingChat(
      participant1Id: participant1Id,
      participant2Id: participant2Id,
    );
    if (existing != null) return existing;

    try {
      final chat = await databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        documentId: ID.unique(),
        data: {
          'participants': [participant1Id, participant2Id],
          'lastMessage': '',
          'lastMessageTime': DateTime.now().toUtc().toIso8601String(),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
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
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        documentId: ID.unique(),
        data: {
          'chatId': chatId,
          'senderId': senderId,
          'text': text,
          'timestamp': now,
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
          'lastMessageTime': now,
        },
      );
    } on AppwriteException catch (e) {
      throw Exception(e.message ?? 'Error al enviar mensaje');
    }
  }

  /// Chat canónico 1:1 (el más activo). Evita hilos duplicados.
  Future<Document> resolveChat({
    required String userId,
    required String otherUserId,
  }) async {
    final existing = await findExistingChat(
      participant1Id: userId,
      participant2Id: otherUserId,
    );
    if (existing != null) return existing;
    return createChat(
      participant1Id: userId,
      participant2Id: otherUserId,
    );
  }

  /// Todos los chatIds entre dos usuarios (por si hubo duplicados).
  Future<List<String>> chatIdsForPair(String userA, String userB) async {
    final ids = <String>{};
    try {
      final all = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [Query.limit(100)],
      );
      for (final chat in all.documents) {
        final parts = parseParticipants(chat.data['participants']);
        if (parts.contains(userA) && parts.contains(userB)) {
          ids.add(chat.$id);
        }
      }
    } catch (e) {
      debugPrint('chatIdsForPair: $e');
    }
    return ids.toList();
  }

  Future<List<Document>> getMessages(String chatId) async {
    List<Document> result = [];
    try {
      final messages = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.orderAsc('\$createdAt'),
          Query.limit(200),
        ],
      );
      result = messages.documents;
    } on AppwriteException catch (e) {
      debugPrint('Error getMessages: ${e.message}');
      try {
        final all = await databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.messagesCollectionId,
          queries: [Query.limit(200)],
        );
        result = all.documents
            .where((m) => m.data['chatId']?.toString() == chatId)
            .toList();
      } catch (_) {
        return [];
      }
    }

    result.sort((a, b) => messageTime(a).compareTo(messageTime(b)));
    return result;
  }

  /// Mensajes de todos los chats entre dos personas (fusiona duplicados).
  /// [knownChatIds] evita volver a listar todos los chats (caro).
  Future<List<Document>> getMessagesForPair({
    required String userId,
    required String otherUserId,
    String? primaryChatId,
    List<String>? knownChatIds,
  }) async {
    final chatIds = <String>{
      ...?knownChatIds,
      if (primaryChatId != null && primaryChatId.isNotEmpty) primaryChatId,
    };
    if (chatIds.isEmpty) {
      chatIds.addAll(await chatIdsForPair(userId, otherUserId));
    }
    if (chatIds.isEmpty) return [];

    final byId = <String, Document>{};
    // En paralelo, no uno tras otro
    final batches = await Future.wait(
      chatIds.map(getMessages),
    );
    for (final msgs in batches) {
      for (final m in msgs) {
        byId[m.$id] = m;
      }
    }
    final result = byId.values.toList();
    result.sort((a, b) => messageTime(a).compareTo(messageTime(b)));
    return result;
  }

  /// Chats del usuario, **sin duplicados** (1 chat por pareja).
  Future<List<Document>> getUserChats(String userId) async {
    List<Document> raw = [];

    try {
      final chats = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [
          Query.equal('participants', userId),
          Query.limit(100),
        ],
      );
      raw = chats.documents;
    } catch (_) {}

    if (raw.isEmpty) {
      try {
        final allChats = await databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.chatsCollectionId,
          queries: [Query.limit(100)],
        );
        raw = allChats.documents.where((doc) {
          return parseParticipants(doc.data['participants']).contains(userId);
        }).toList();
      } on AppwriteException catch (e) {
        debugPrint('Error en getUserChats fallback: ${e.message}');
        return [];
      }
    }

    // Deduplicar por pareja de participantes: quedarse con el más reciente / con mensajes
    final Map<String, Document> bestByPair = {};
    for (final chat in raw) {
      final parts = parseParticipants(chat.data['participants']);
      if (parts.length < 2) continue;
      // Ignorar chats de prueba
      if (parts.contains('a') || parts.contains('b')) continue;

      final other = parts.firstWhere((id) => id != userId, orElse: () => '');
      if (other.isEmpty) continue;

      final key = _pairKey(userId, other);
      final existing = bestByPair[key];
      if (existing == null) {
        bestByPair[key] = chat;
        continue;
      }

      final existingScore = _chatScore(existing);
      final newScore = _chatScore(chat);
      if (newScore >= existingScore) {
        bestByPair[key] = chat;
      }
    }

    final result = bestByPair.values.toList();
    result.sort((a, b) => _chatActivity(b).compareTo(_chatActivity(a)));
    return result;
  }

  static DateTime _chatActivity(Document chat) {
    return DateTime.tryParse(chat.$updatedAt)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _chatScore(Document chat) {
    final last = (chat.data['lastMessage'] ?? '').toString();
    var score = _chatActivity(chat).millisecondsSinceEpoch ~/ 1000;
    if (last.isNotEmpty) score += 1000000000;
    return score;
  }

  Future<Document?> findExistingChat({
    required String participant1Id,
    required String participant2Id,
  }) async {
    try {
      Document? best;
      // Una sola lectura de chats (sin cascadas de requests).
      try {
        final filtered = await databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.chatsCollectionId,
          queries: [
            Query.equal('participants', participant1Id),
            Query.limit(100),
          ],
        );
        for (final chat in filtered.documents) {
          final parts = parseParticipants(chat.data['participants']);
          if (parts.contains(participant1Id) && parts.contains(participant2Id)) {
            if (best == null || _chatScore(chat) > _chatScore(best)) {
              best = chat;
            }
          }
        }
      } catch (_) {}

      if (best != null) return best;

      final all = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        queries: [Query.limit(100)],
      );
      for (final chat in all.documents) {
        final parts = parseParticipants(chat.data['participants']);
        if (parts.contains(participant1Id) && parts.contains(participant2Id)) {
          if (best == null || _chatScore(chat) > _chatScore(best)) {
            best = chat;
          }
        }
      }
      return best;
    } catch (e) {
      debugPrint('Error en findExistingChat: $e');
      return null;
    }
  }

  /// Mensajes + (opcional) el documento del otro usuario (typing/online).
  RealtimeSubscription subscribeToChat({
    required String chatId,
    String? otherUserId,
  }) {
    final channels = <String>[
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.messagesCollectionId}.documents',
    ];
    if (otherUserId != null && otherUserId.isNotEmpty) {
      channels.add(
        'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.usersCollectionId}.documents.$otherUserId',
      );
    }
    return realtime.subscribe(channels);
  }

  Future<List<Document>> searchUsers(String query) async {
    try {
      final users = await databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [Query.limit(50)],
      );
      final q = query.toLowerCase();
      return users.documents.where((u) {
        final name = (u.data['name'] ?? '').toString().toLowerCase();
        final phone = (u.data['phone'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q);
      }).toList();
    } on AppwriteException catch (e) {
      debugPrint('Error en searchUsers: ${e.message}');
      return [];
    }
  }
}
