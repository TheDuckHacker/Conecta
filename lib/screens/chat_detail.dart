import 'dart:async';

import 'package:flutter/material.dart';
import 'package:appwrite/models.dart';
import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import 'package:conecta_lsb/services/chat_service.dart';
import 'package:conecta_lsb/services/contact_service.dart';
import 'package:conecta_lsb/screens/video_call_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String name;
  final String avatar;
  final bool isActive;
  final String currentUserId;
  final String? otherUserId;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.name,
    required this.avatar,
    this.isActive = false,
    required this.currentUserId,
    this.otherUserId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatService = ChatService();
  final _contactService = ContactService();
  final _focusNode = FocusNode();
  List<Document> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isOnline = false;
  String _chatId = '';
  final Set<String> _pairChatIds = {};
  RealtimeSubscription? _subscription;
  StreamSubscription? _realtimeListen;
  Timer? _pollTimer;
  Timer? _statusTimer;
  bool _isFetching = false;

  static const _accent = Color(0xff37C8F2);
  static const _textDark = Color(0xff1A3A4A);
  static const _textMuted = Color(0xff5A7A8A);
  static const _headerBg = Color(0xff2BB8E0);

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId;
    _isOnline = widget.isActive;
    _initChat();
  }

  Future<void> _initChat() async {
    final otherId = widget.otherUserId;
    try {
      // Siempre usar el chat canónico de la pareja (evita hilos duplicados).
      if (otherId != null && otherId.isNotEmpty) {
        final chat = await _chatService.resolveChat(
          userId: widget.currentUserId,
          otherUserId: otherId,
        );
        _chatId = chat.$id;
        final pairIds = await _chatService.chatIdsForPair(
          widget.currentUserId,
          otherId,
        );
        _pairChatIds
          ..clear()
          ..addAll(pairIds)
          ..add(_chatId);
      } else if (_chatId.isNotEmpty) {
        _pairChatIds
          ..clear()
          ..add(_chatId);
      }
    } catch (e) {
      debugPrint('Error resolving chat: $e');
    }

    // Primera carga: fusiona duplicados una sola vez.
    await Future.wait([
      _loadMessages(scroll: true, mergePair: true),
      _refreshOtherUserStatus(),
    ]);
    _subscribeToMessages();
  }

  Future<void> _refreshOtherUserStatus() async {
    final otherId = widget.otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    try {
      final user = await _contactService.getUserById(otherId);
      final online = (user?.data['status'] ?? '') == 'online';
      if (!mounted) return;
      if (online != _isOnline) {
        setState(() => _isOnline = online);
      }
    } catch (e) {
      debugPrint('Error status: $e');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    _realtimeListen?.cancel();
    _subscription?.close();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sortMessages() {
    _messages.sort(
      (a, b) => ChatService.messageTime(a).compareTo(ChatService.messageTime(b)),
    );
  }

  Future<void> _loadMessages({
    bool scroll = false,
    bool mergePair = false,
  }) async {
    if (_isFetching) return;
    if (_chatId.isEmpty && _pairChatIds.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _isFetching = true;
    try {
      List<Document> loaded;
      final otherId = widget.otherUserId;

      // mergePair solo al abrir: después solo el chat canónico (rápido).
      if (mergePair && otherId != null && otherId.isNotEmpty) {
        loaded = await _chatService.getMessagesForPair(
          userId: widget.currentUserId,
          otherUserId: otherId,
          primaryChatId: _chatId,
          knownChatIds: _pairChatIds.toList(),
        );
      } else {
        loaded = await _chatService.getMessages(_chatId);
      }

      final same = loaded.length == _messages.length &&
          (loaded.isEmpty ||
              (loaded.isNotEmpty &&
                  _messages.isNotEmpty &&
                  loaded.last.$id == _messages.last.$id &&
                  loaded.first.$id == _messages.first.$id));

      if (!mounted) return;

      if (!same) {
        setState(() {
          _messages = List<Document>.from(loaded);
          _sortMessages();
          _isLoading = false;
        });
        if (scroll) _scrollToBottom();
      } else if (_isLoading) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    } finally {
      _isFetching = false;
    }
  }

  bool _isRelevantChatId(String? chatId) {
    if (chatId == null || chatId.isEmpty) return false;
    if (chatId == _chatId) return true;
    return _pairChatIds.contains(chatId);
  }

  void _subscribeToMessages() {
    _realtimeListen?.cancel();
    _subscription?.close();
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    if (_chatId.isEmpty && _pairChatIds.isEmpty) return;

    try {
      _subscription = _chatService.subscribeToMessages(_chatId);
      _realtimeListen = _subscription!.stream.listen(
        (event) {
          if (!mounted) return;
          final payload = event.payload;
          if (payload.isEmpty) return;

          final eventChatId = payload['chatId']?.toString();
          if (!_isRelevantChatId(eventChatId)) return;

          final events = event.events;
          final isDelete = events.any((e) => e.contains('.delete'));
          if (isDelete) {
            final id = payload['\$id']?.toString();
            if (id != null) {
              setState(() => _messages.removeWhere((m) => m.$id == id));
            }
            return;
          }

          // Recarga liviana: solo el chat activo
          _loadMessages(scroll: true);
        },
        onError: (e) => debugPrint('Realtime error: $e'),
        onDone: () => debugPrint('Realtime cerrado'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('No se pudo suscribir a realtime: $e');
    }

    // Poll liviano (1 sola request). No fusionar pares en cada tick.
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadMessages();
    });

    // Estado online mucho menos frecuente
    _statusTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) _refreshOtherUserStatus();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _chatId.isEmpty) return;

    _messageController.clear();
    setState(() => _isSending = true);

    try {
      await _chatService.sendMessage(
        chatId: _chatId,
        senderId: widget.currentUserId,
        text: text,
      );
      await _loadMessages(scroll: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _startVideoCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          userName: widget.name,
          userAvatar: widget.avatar,
          isVideoCall: true, // App LSB: siempre videollamada (señas)
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffE8F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildMessagesArea()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _headerBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                backgroundImage: widget.avatar.isNotEmpty ? NetworkImage(widget.avatar) : null,
                onBackgroundImageError: widget.avatar.isNotEmpty ? (_, __) {} : null,
                child: widget.avatar.isEmpty
                    ? Text(
                        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: _headerBg,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isOnline ? const Color(0xff2ECC71) : Colors.white70,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isOnline ? 'En línea' : 'Desconectado',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Solo videollamada (app para personas sordas / LSB)
              Tooltip(
                message: 'Videollamada LSB',
                child: IconButton(
                  onPressed: _startVideoCall,
                  icon: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesArea() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: _accent, size: 34),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sin mensajes aún',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Escribe algo y empieza la conversación',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.data['senderId']?.toString() == widget.currentUserId;
        final showTail = index == _messages.length - 1 ||
            _messages[index + 1].data['senderId']?.toString() !=
                msg.data['senderId']?.toString();

        final date = ChatService.messageTime(msg);
        final previous =
            index == 0 ? null : ChatService.messageTime(_messages[index - 1]);
        final showDate = previous == null || !_sameDay(previous, date);

        final bubble = _buildMessageBubble(
          text: (msg.data['text'] ?? '').toString(),
          time: _formatTime(date),
          isMe: isMe,
          showTail: showTail,
        );

        if (!showDate) return bubble;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_buildDateChip(date), bubble],
        );
      },
    );
  }

  Widget _buildDateChip(DateTime date) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _formatDate(date),
            style: const TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_sameDay(date, now)) return 'Hoy';
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) return 'Ayer';
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildMessageBubble({
    required String text,
    required String time,
    required bool isMe,
    required bool showTail,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: showTail ? 10 : 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
        decoration: BoxDecoration(
          // Tú: azul sólido. Otro: blanco sólido (siempre legible)
          color: isMe ? _accent : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : (showTail ? 4 : 18)),
            bottomRight: Radius.circular(isMe ? (showTail ? 4 : 18) : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: isMe ? Colors.white : _textDark,
                  fontSize: 15.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  time,
                  style: TextStyle(
                    color: isMe ? Colors.white.withValues(alpha: 0.85) : _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xffF0F7FA),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      color: _textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Escribe un mensaje...',
                      hintStyle: TextStyle(color: _textMuted, fontSize: 15),
                      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _isSending ? null : _sendMessage,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                  child: _isSending
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
