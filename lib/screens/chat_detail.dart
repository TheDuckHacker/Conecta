import 'package:flutter/material.dart';
import 'package:appwrite/models.dart';
import 'package:conecta_lsb/services/chat_service.dart';
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
  final _focusNode = FocusNode();
  List<Document> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String _chatId = '';

  static const _accent = Color(0xff37C8F2);
  static const _textDark = Color(0xff1A3A4A);
  static const _textMuted = Color(0xff6B9BB0);

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId;
    _initChat();
  }

  Future<void> _initChat() async {
    if (_chatId.isEmpty && widget.otherUserId != null) {
      try {
        Document? existingChat = await _chatService.findExistingChat(
          participant1Id: widget.currentUserId,
          participant2Id: widget.otherUserId!,
        );
        existingChat ??= await _chatService.createChat(
          participant1Id: widget.currentUserId,
          participant2Id: widget.otherUserId!,
        );
        _chatId = existingChat.$id;
      } catch (e) {
        debugPrint('Error creating chat: $e');
      }
    }
    await _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (_chatId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      _messages = await _chatService.getMessages(_chatId);
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _subscribeToMessages() {
    if (_chatId.isEmpty) return;
    _chatService.subscribeToMessages(_chatId).listen((event) {
      if (mounted) {
        _loadMessages();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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
      await _loadMessages();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xffE8F8FC),
              Color(0xffB8EAF5),
              Color(0xff7DD4EF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessagesArea()),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.35), width: 1),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                backgroundImage: widget.avatar.isNotEmpty ? NetworkImage(widget.avatar) : null,
                onBackgroundImageError: widget.avatar.isNotEmpty ? (_, __) {} : null,
                child: widget.avatar.isEmpty
                    ? Text(
                        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
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
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: widget.isActive ? const Color(0xff2ECC71) : Colors.white54,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.isActive ? 'En línea' : 'Desconectado',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoCallScreen(
                      userName: widget.name,
                      userAvatar: widget.avatar,
                      isVideoCall: true,
                    ),
                  ),
                );
              },
              icon: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 20),
              ),
            ),
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoCallScreen(
                      userName: widget.name,
                      userAvatar: widget.avatar,
                      isVideoCall: false,
                    ),
                  ),
                );
              },
              icon: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_rounded, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesArea() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
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
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sin mensajes aún',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Escribe algo y empieza la conversación',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.data['senderId'] == widget.currentUserId;
        final showTail = index == _messages.length - 1 ||
            _messages[index + 1].data['senderId'] != msg.data['senderId'];

        return _buildMessageBubble(
          text: msg.data['text'] ?? '',
          time: _formatTime(msg.data['timestamp'] ?? ''),
          isMe: isMe,
          showTail: showTail,
        );
      },
    );
  }

  String _formatTime(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
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
        margin: EdgeInsets.only(bottom: showTail ? 12 : 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 8),
        decoration: BoxDecoration(
          color: isMe ? Colors.white : Colors.white.withValues(alpha: 0.32),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isMe ? 22 : (showTail ? 6 : 22)),
            bottomRight: Radius.circular(isMe ? (showTail ? 6 : 22) : 22),
          ),
          border: isMe
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isMe ? 0.07 : 0.04),
              blurRadius: isMe ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe ? _textDark : Colors.white,
                fontSize: 15.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(
                  color: isMe ? _textMuted : Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: _accent, fontSize: 16, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Escribe un mensaje...',
                    hintStyle: TextStyle(
                      color: _accent.withValues(alpha: 0.45),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    prefixIcon: Icon(
                      Icons.emoji_emotions_outlined,
                      color: _accent.withValues(alpha: 0.4),
                      size: 22,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isSending ? null : _sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.38),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
    );
  }
}
