import 'package:flutter/material.dart';
import 'package:appwrite/models.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/chat_service.dart';
import 'package:conecta_lsb/services/contact_service.dart';
import 'package:conecta_lsb/screens/chat_detail.dart';
import 'package:conecta_lsb/screens/add_contact_screen.dart';

class HomeTab extends StatefulWidget {
  final VoidCallback onStartCamera;

  const HomeTab({
    super.key,
    required this.onStartCamera,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _authService = AuthService();
  final _chatService = ChatService();
  final _contactService = ContactService();

  User? _currentUser;
  List<Document> _chats = [];
  List<Document> _contactUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      _currentUser = await _authService.getCurrentUser();
      if (_currentUser != null) {
        _contactService.clearCache();
        _chats = await _chatService.getUserChats(_currentUser!.$id);
        _contactUsers = await _contactService.getContacts(_currentUser!.$id);
      }
    } catch (e) {
      debugPrint('Error cargando home tab: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final userName = _currentUser?.name.isNotEmpty == true
        ? _currentUser!.name
        : 'Bienvenido';

    return Container(
      color: Colors.transparent,
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // GREETING
                Text(
                  "¡Hola, $userName!",
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff121B35),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "¿Qué quieres comunicar hoy?",
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xff5A6E85),
                  ),
                ),
                const SizedBox(height: 25),

                // TRANSLATION CARD
                _buildTranslationCard(),

                const SizedBox(height: 30),

                // RECENT CONTACTS
                _buildRecentContactsHeader(),
                const SizedBox(height: 15),
                _buildRecentContactsList(),

                const SizedBox(height: 30),

                // RECENT CHATS
                _buildRecentChatsHeader(),
                const SizedBox(height: 15),
                _buildRecentChatsList(),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTranslationCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xff27C7D9),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xff27C7D9).withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Traducción en Vivo",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff121B35),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Convierte LSB a texto al instante",
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xff5A6E85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: widget.onStartCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff27C7D9),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xff27C7D9).withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "Iniciar Cámara",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentContactsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "MIS CONTACTOS",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Color(0xff5A6E85),
          ),
        ),
        GestureDetector(
          onTap: () async {
            final res = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddContactScreen()),
            );
            if (res == true) _loadData();
          },
          child: const Text(
            "+ Agregar",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xff27C7D9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentContactsList() {
    if (_isLoading) {
      return const SizedBox(
        height: 60,
        child: Center(
            child: CircularProgressIndicator(color: Color(0xff27C7D9))),
      );
    }

    if (_contactUsers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_add_rounded,
                color: Color(0xff27C7D9), size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "No tienes contactos agregados aún.",
                style: TextStyle(color: Color(0xff5A6E85), fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddContactScreen()),
                );
                if (res == true) _loadData();
              },
              child: const Text("Agregar",
                  style: TextStyle(
                      color: Color(0xff27C7D9), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _contactUsers.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final user = _contactUsers[index];
          final rawName = (user.data['name'] ?? '').toString();
          final phone = (user.data['phone'] ?? '').toString();
          final name = (rawName.isNotEmpty && rawName != 'Usuario')
              ? rawName
              : (phone.isNotEmpty ? phone : 'Contacto');
          final avatar = user.data['avatar'] ?? '';
          final status = user.data['status'] ?? 'offline';
          final isOnline = status == 'online';

          return GestureDetector(
            onTap: () => _startChat(user),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xffCDEFF7),
                      backgroundImage:
                          avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      onBackgroundImageError:
                          avatar.isNotEmpty ? (_, __) {} : null,
                      child: avatar.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Color(0xff27C7D9),
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    if (isOnline)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xff2ECC71),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 60,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff121B35),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentChatsHeader() {
    return const Text(
      "CHATS RECIENTES",
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: Color(0xff5A6E85),
      ),
    );
  }

  Widget _buildRecentChatsList() {
    if (_isLoading) {
      return const SizedBox(
        height: 60,
        child: Center(
            child: CircularProgressIndicator(color: Color(0xff27C7D9))),
      );
    }

    if (_chats.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                color: Color(0xff5A6E85), size: 32),
            SizedBox(height: 8),
            Text(
              "Sin conversaciones recientes",
              style: TextStyle(
                color: Color(0xff121B35),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              "Agrega un contacto para iniciar un chat.",
              style: TextStyle(color: Color(0xff5A6E85), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _chats.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final chat = _chats[index];
        final otherUserId =
            ChatService.otherParticipantId(chat, _currentUser!.$id);

        return FutureBuilder<Document?>(
          future: _getUserInfo(otherUserId),
          builder: (context, snapshot) {
            final otherUser = snapshot.data;
            final rawName = (otherUser?.data['name'] ?? '').toString();
            final rawPhone = (otherUser?.data['phone'] ?? '').toString();
            var name = (rawName.isNotEmpty && rawName != 'Usuario')
                ? rawName
                : (rawPhone.isNotEmpty ? rawPhone : 'Contacto');
            if (otherUserId.isEmpty || otherUserId == _currentUser!.$id) {
              name = 'Contacto';
            }
            final avatar = otherUser?.data['avatar'] ?? '';
            final lastMessage = chat.data['lastMessage'] ?? '';
            final updatedAt = chat.data['updatedAt']?.toString() ?? chat.data['lastMessageTime']?.toString() ?? '';

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(
                      chatId: chat.$id,
                      name: name,
                      avatar: avatar,
                      isActive: false,
                      currentUserId: _currentUser!.$id,
                      otherUserId: otherUserId.isNotEmpty ? otherUserId : null,
                    ),
                  ),
                ).then((_) => _loadData());
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xffCDEFF7),
                      backgroundImage:
                          avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      onBackgroundImageError:
                          avatar.isNotEmpty ? (_, __) {} : null,
                      child: avatar.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: Color(0xff121B35),
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Color(0xff121B35),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            lastMessage.toString().isEmpty
                                ? 'Inicia la conversación...'
                                : lastMessage.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff5A6E85),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (updatedAt.isNotEmpty)
                      Text(
                        _formatTime(updatedAt),
                        style: const TextStyle(
                          color: Color(0xffA8B8C0),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startChat(Document user) async {
    if (_currentUser == null) return;
    try {
      Document? existingChat = await _chatService.findExistingChat(
        participant1Id: _currentUser!.$id,
        participant2Id: user.$id,
      );

      existingChat ??= await _chatService.createChat(
        participant1Id: _currentUser!.$id,
        participant2Id: user.$id,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              chatId: existingChat!.$id,
              name: user.data['name'] ?? 'Usuario',
              avatar: user.data['avatar'] ?? '',
              isActive: false,
              currentUserId: _currentUser!.$id,
              otherUserId: user.$id,
            ),
          ),
        ).then((_) => _loadData());
      }
    } catch (e) {
      debugPrint('Error starting chat: $e');
    }
  }

  Future<Document?> _getUserInfo(String userId) async {
    return await _contactService.getUserById(userId);
  }

  String _formatTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
