import 'package:flutter/material.dart';
import 'package:appwrite/models.dart';
import 'package:conecta_lsb/screens/chat_detail.dart';
import 'package:conecta_lsb/screens/user_profile.dart';
import 'package:conecta_lsb/screens/add_contact_screen.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/chat_service.dart';
import 'package:conecta_lsb/services/contact_service.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  bool _isChatsTabSelected = true;
  String _searchQuery = "";
  final _authService = AuthService();
  final _chatService = ChatService();
  final _contactService = ContactService();

  User? _currentUser;
  List<Document> _chats = [];
  List<Document> _contactUsers = [];
  bool _isLoading = true;

  static const _accent = Color(0xff37C8F2);
  static const _textDark = Color(0xff1A3A4A);
  static const _textMuted = Color(0xff6B9BB0);

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
        // Solo contactos que el usuario agregó explícitamente
        _contactUsers = await _contactService.getContacts(_currentUser!.$id);
      }
    } catch (e) {
      debugPrint('Error cargando datos de chats/contactos: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _openAddContactScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddContactScreen()),
    );
    if (result == true) {
      setState(() => _isLoading = true);
      _loadData();
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al crear chat: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmRemoveContact(Document user) async {
    final name = user.data['name'] ?? 'este contacto';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar contacto'),
        content: Text(
            '¿Quitar a $name de tus contactos? El chat se mantiene.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _contactService.removeContact(user.$id);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contacto eliminado'),
              backgroundColor: Color(0xff37C8F2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredChats = _chats.where((chat) {
      return chat.data['lastMessage']
          .toString()
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();

    // Solo contactos que el usuario agregó
    final filteredContacts = _contactUsers.where((user) {
      final name = (user.data['name'] ?? '').toString().toLowerCase();
      final phone = (user.data['phone'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Mensajes',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                      IconButton(
                        onPressed: _openAddContactScreen,
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_add_rounded,
                              color: _accent, size: 22),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isChatsTabSelected
                        ? '${filteredChats.length} conversaciones'
                        : '${filteredContacts.length} contactos',
                    style: const TextStyle(color: _textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  _buildSearchBar(),
                  const SizedBox(height: 18),
                  _buildTabSwitcher(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _isChatsTabSelected
                        ? _buildChatList(filteredChats)
                        : _buildContactList(filteredContacts),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              right: 24,
              child: GestureDetector(
                onTap: () {
                  if (!_isChatsTabSelected) {
                    _openAddContactScreen();
                  } else {
                    setState(() => _isChatsTabSelected = false);
                  }
                },
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.40),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isChatsTabSelected
                        ? Icons.edit_rounded
                        : Icons.person_add_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              color: _accent.withValues(alpha: 0.55), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              style: const TextStyle(
                  color: _accent, fontSize: 15, fontWeight: FontWeight.w500),
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Buscar chats o contactos',
                hintStyle: TextStyle(
                  color: _accent.withValues(alpha: 0.4),
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTabChip('Chats', _isChatsTabSelected, () {
            setState(() => _isChatsTabSelected = true);
          })),
          Expanded(child: _buildTabChip('Contactos', !_isChatsTabSelected, () {
            setState(() => _isChatsTabSelected = false);
          })),
        ],
      ),
    );
  }

  Widget _buildTabChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? _accent : Colors.white.withValues(alpha: 0.85),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? actionWidget,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: _accent, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: _textDark,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _textMuted, fontSize: 14, height: 1.4),
            ),
            if (actionWidget != null) ...[
              const SizedBox(height: 20),
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(List<Document> chats) {
    if (chats.isEmpty) {
      return _buildEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Sin chats recientes',
        subtitle: 'Ve a Contactos y empieza una conversación nueva',
        actionWidget: ElevatedButton.icon(
          onPressed: () => setState(() => _isChatsTabSelected = false),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.people_outline_rounded, color: Colors.white),
          label: const Text('Ver contactos',
              style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: chats.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final chat = chats[index];
        final otherUserId =
            ChatService.otherParticipantId(chat, _currentUser!.$id);

        return FutureBuilder<Document?>(
          future: _getUserInfo(otherUserId),
          builder: (context, snapshot) {
            final otherUser = snapshot.data;
            final rawName = (otherUser?.data['name'] ?? '').toString();
            final rawPhone = (otherUser?.data['phone'] ?? '').toString();
            // Nunca mostrar el nombre del usuario actual como "otro"
            var name = (rawName.isNotEmpty && rawName != 'Usuario')
                ? rawName
                : (rawPhone.isNotEmpty ? rawPhone : 'Contacto');
            if (otherUserId.isEmpty || otherUserId == _currentUser!.$id) {
              name = 'Contacto';
            }
            final avatar = otherUser?.data['avatar'] ?? '';
            final lastMessage = chat.data['lastMessage'] ?? '';
            final updatedAt = chat.data['updatedAt']?.toString() ??
                chat.data['lastMessageTime']?.toString() ??
                '';

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(22),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.85)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xffCDEFF7),
                      backgroundImage:
                          avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      onBackgroundImageError:
                          avatar.isNotEmpty ? (_, __) {} : null,
                      child: avatar.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    color: _textDark,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (updatedAt.isNotEmpty)
                                Text(
                                  _formatListTime(updatedAt),
                                  style: TextStyle(
                                    color: _textMuted.withValues(alpha: 0.9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            lastMessage.toString().isEmpty
                                ? 'Inicia la conversación...'
                                : lastMessage.toString(),
                            style: const TextStyle(
                                color: _textMuted, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded,
                        color: _accent.withValues(alpha: 0.45), size: 22),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatListTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildContactList(List<Document> users) {
    if (users.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_add_alt_1_rounded,
        title: 'Sin contactos guardados',
        subtitle:
            'Agrega contactos usando su número de teléfono para chatear fácilmente con ellos.',
        actionWidget: ElevatedButton.icon(
          onPressed: _openAddContactScreen,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: const Icon(Icons.person_add_rounded, color: Colors.white),
          label: const Text('Agregar contacto',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: users.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = users[index];
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
          onLongPress: () => _confirmRemoveContact(user),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
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
                                color: _accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 1,
                      right: 1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xff2ECC71)
                              : const Color(0xffB0BEC5),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phone.isNotEmpty
                            ? phone
                            : (isOnline ? 'En línea' : 'Desconectado'),
                        style: TextStyle(
                          color: isOnline && phone.isEmpty
                              ? const Color(0xff2ECC71)
                              : _textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.chat_bubble_rounded,
                        color: _accent, size: 18),
                    onPressed: () => _startChat(user),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 20),
                  onPressed: () => _confirmRemoveContact(user),
                ),
                IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      color: _textMuted.withValues(alpha: 0.8), size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(
                          userId: user.$id,
                          currentUserId: _currentUser!.$id,
                        ),
                      ),
                    ).then((_) => _loadData());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Document?> _getUserInfo(String userId) async {
    return await _contactService.getUserById(userId);
  }
}
