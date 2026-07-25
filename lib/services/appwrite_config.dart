import 'package:appwrite/appwrite.dart';

class AppwriteConfig {
  static const String endpoint = 'https://nyc.cloud.appwrite.io/v1';
  static const String projectId = '6a642272001254359727';
  static const String databaseId = '6a6425090024980c8b80';
  static const String usersCollectionId = 'users';
  static const String chatsCollectionId = 'chats';
  static const String messagesCollectionId = 'messages';
}

final Client appwriteClient = Client()
    .setEndpoint(AppwriteConfig.endpoint)
    .setProject(AppwriteConfig.projectId)
    .setSelfSigned(status: true);

final Account account = Account(appwriteClient);
final Databases databases = Databases(appwriteClient);
final Realtime realtime = Realtime(appwriteClient);
