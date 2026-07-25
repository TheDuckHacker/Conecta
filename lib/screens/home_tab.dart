import 'package:flutter/material.dart';

class HomeTab extends StatelessWidget {
  final VoidCallback onStartCamera;

  const HomeTab({
    super.key,
    required this.onStartCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent, // Transparent to let main gradient show
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // GREETING
                const Text(
                  "¡Hola, Carla!",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff121B35), // Dark primary text
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "¿Qué quieres comunicar hoy?",
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xff5A6E85), // Grey secondary text
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
              // Glowing video icon container
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xff27C7D9), // Turquoise Accent
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
          // Action button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onStartCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff27C7D9), // Turquoise
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
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "CONTACTOS RECIENTES",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Color(0xff5A6E85),
          ),
        ),
        Text(
          "Ver todos",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xff27C7D9),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentContactsList() {
    final contacts = [
      {'name': 'Elena', 'avatar': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150', 'active': true},
      {'name': 'Mateo', 'avatar': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150', 'active': false},
      {'name': 'Sofía', 'avatar': 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150', 'active': false},
      {'name': 'Ricardo', 'avatar': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150', 'active': false},
    ];

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: contacts.length,
        separatorBuilder: (context, index) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final contact = contacts[index];
          final isActive = contact['active'] as bool;
          return Column(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive ? const Color(0xff2ECC71) : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xffCDEFF7),
                      backgroundImage: NetworkImage(contact['avatar'] as String),
                      onBackgroundImageError: (_, __) {},
                      child: Text(
                        (contact['name'] as String)[0],
                        style: const TextStyle(color: Color(0xff121B35), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (isActive)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xff2ECC71),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xffE5F7FF), width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                contact['name'] as String,
                style: const TextStyle(
                  color: Color(0xff121B35),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
    final chats = [
      {
        'name': 'Elena Martínez',
        'avatar': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
        'message': 'Hola',
        'time': '14:30',
        'active': true,
        'sent': true,
      },
      {
        'name': 'Mateo Silva',
        'avatar': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
        'message': 'Enviado un mensaje',
        'time': 'Ayer',
        'active': true,
        'sent': false,
      },
      {
        'name': 'Comunidad Sordos GDL',
        'avatar': 'https://images.unsplash.com/photo-1582213782179-e0d53f98f2ca?w=150',
        'message': 'Juan: Bienvenidos a los nuevos miembros!',
        'time': 'Martes',
        'active': false,
        'sent': false,
      },
    ];

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chats.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final chat = chats[index];
        final isActive = chat['active'] as bool;
        final isSent = chat['sent'] as bool;
        return Container(
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
              // Chat avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xffCDEFF7),
                    backgroundImage: NetworkImage(chat['avatar'] as String),
                    onBackgroundImageError: (_, __) {},
                    child: Text(
                      (chat['name'] as String)[0],
                      style: const TextStyle(color: Color(0xff121B35), fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (isActive)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xff2ECC71),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Message details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat['name'] as String,
                      style: const TextStyle(
                        color: Color(0xff121B35),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (isSent) ...[
                          const Icon(
                            Icons.done_all_rounded,
                            size: 16,
                            color: Color(0xff27C7D9),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            chat['message'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff5A6E85),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Time
              Text(
                chat['time'] as String,
                style: const TextStyle(
                  color: Color(0xffA8B8C0),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
