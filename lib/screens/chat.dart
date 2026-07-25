import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/home_tab.dart';
import 'package:conecta_lsb/screens/chats_tab.dart';
import 'package:conecta_lsb/screens/profile.dart';
import 'package:conecta_lsb/services/auth_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  int _currentIndex = 0;

  // Pages to display in the body
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeTab(
        onStartCamera: () {
          setState(() {
            _currentIndex = 2; // Navigate to Translation Tab (Center Camera)
          });
        },
      ),
      const ChatsTab(),
      const TranslationTab(),
      const AcademyTab(),
      const SettingsTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Prevents back button on main screen
        backgroundColor: const Color(0xff27C7D9), // Turquoise matching requirements
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            // User Avatar
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                backgroundImage: NetworkImage('https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150'),
                child: Icon(Icons.person, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            // App Title
            const Text(
              "Conecta",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          // Notification Bell
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 26),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("No tienes nuevas notificaciones"),
                  backgroundColor: Color(0xff27C7D9),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xffE5F7FF),
              Color(0xffCDEFF7),
              Color(0xffA9E0F3),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: _buildCustomBottomNavigationBar(),
    );
  }

  Widget _buildCustomBottomNavigationBar() {
    return Container(
      height: 75,
      decoration: BoxDecoration(
        color: const Color(0xff27C7D9), // Solid turquoise matching app bar
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            spreadRadius: 1,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Home Button
          _buildNavIconButton(
            icon: Icons.home_rounded,
            index: 0,
          ),
          // Chat Button
          _buildNavIconButton(
            icon: Icons.chat_bubble_rounded,
            index: 1,
          ),
          // Center Camera Button (Translation Tab)
          GestureDetector(
            onTap: () {
              setState(() {
                _currentIndex = 2;
              });
            },
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xffFFFFFF), // Soft glowing white
                    Color(0xffE5F7FF),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Color(0xff27C7D9), // Turquoise icon inside
                size: 28,
              ),
            ),
          ),
          // Academy Button
          _buildNavIconButton(
            icon: Icons.school_rounded,
            index: 3,
          ),
          // Settings Button
          _buildNavIconButton(
            icon: Icons.settings_rounded,
            index: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildNavIconButton({required IconData icon, required int index}) {
    final isSelected = _currentIndex == index;
    return IconButton(
      icon: Icon(
        icon,
        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.5),
        size: 26,
      ),
      onPressed: () {
        setState(() {
          _currentIndex = index;
        });
      },
    );
  }
}

// ==========================================
// ADDITIONAL HIGH-FIDELITY SIMULATOR TABS
// ==========================================

class TranslationTab extends StatefulWidget {
  const TranslationTab({super.key});

  @override
  State<TranslationTab> createState() => _TranslationTabState();
}

class _TranslationTabState extends State<TranslationTab> with SingleTickerProviderStateMixin {
  late AnimationController _scannerController;
  String _detectedText = "Espere...";
  int _currentStep = 0;

  final List<String> _simulatedOutputs = [
    "Espere...",
    "Buscando manos...",
    "Gesto detectado: H-O-L-A",
    "Hola",
    "Gesto detectado: C-O-M-O",
    "Cómo",
    "Gesto detectado: E-S-T-A-S",
    "Estás",
    "Hola, ¿cómo estás?",
  ];

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _simulateDetection();
  }

  void _simulateDetection() async {
    for (int i = 0; i < _simulatedOutputs.length; i++) {
      if (!mounted) return;
      await Future.delayed(Duration(seconds: i == 0 ? 1 : 2));
      if (!mounted) return;
      setState(() {
        _currentStep = i;
        _detectedText = _simulatedOutputs[i];
      });
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          // Viewfinder Container
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    // Camera Placeholder Image
                    Container(
                      color: const Color(0xff121B35),
                      width: double.infinity,
                      height: double.infinity,
                      child: Center(
                        child: Icon(
                          Icons.front_hand_rounded,
                          size: 100,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    // Camera Silhouette Overlay
                    Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24, width: 2),
                          borderRadius: BorderRadius.circular(110),
                        ),
                      ),
                    ),
                    // Scanning line animation
                    AnimatedBuilder(
                      animation: _scannerController,
                      builder: (context, child) {
                        return Positioned(
                          top: MediaQuery.of(context).size.height * 0.45 * _scannerController.value,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: const BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xff27C7D9),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // Top controls overlay
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                CircleAvatar(radius: 4, backgroundColor: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  "REC LSB",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white),
                              onPressed: () {},
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Translated Text Output Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.translate_rounded, color: Color(0xff27C7D9), size: 18),
                    SizedBox(width: 8),
                    Text(
                      "TRADUCCIÓN DETECTADA",
                      style: TextStyle(
                        color: Color(0xffA8B8C0),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _detectedText,
                  style: TextStyle(
                    color: _currentStep >= 2 ? const Color(0xff121B35) : const Color(0xffA8B8C0),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Copy text or TTS
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Copiado al portapapeles: '¡Hola, ¿cómo estás!'"),
                              backgroundColor: Color(0xff27C7D9),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff27C7D9),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text("Copiar Texto"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xff27C7D9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.volume_up_rounded, color: Colors.white),
                        onPressed: () {
                          // TTS speaking simulated
                        },
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AcademyTab extends StatelessWidget {
  const AcademyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final courses = [
      {
        'title': 'Alfabeto Dactilológico LSB',
        'desc': 'Aprende las 27 letras del abecedario en lengua de señas.',
        'progress': 0.85,
        'level': 'Básico',
        'icon': Icons.abc_rounded,
      },
      {
        'title': 'Saludos y Presentaciones',
        'desc': 'Cómo presentarte y saludar formal e informalmente.',
        'progress': 0.40,
        'level': 'Básico',
        'icon': Icons.waving_hand_rounded,
      },
      {
        'title': 'Conversación y Vocabulario Diario',
        'desc': 'Expresiones cotidianas, días, colores y familia.',
        'progress': 0.0,
        'level': 'Intermedio',
        'icon': Icons.forum_rounded,
      },
    ];

    return Container(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Academia LSB",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff121B35),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Domina la Lengua de Señas Boliviana paso a paso.",
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xff5A6E85),
                ),
              ),
              const SizedBox(height: 25),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: courses.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final course = courses[index];
                    final progress = course['progress'] as double;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xffE5F7FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  course['icon'] as IconData,
                                  color: const Color(0xff27C7D9),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xff27C7D9).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        course['level'] as String,
                                        style: const TextStyle(
                                          color: Color(0xff27C7D9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      course['title'] as String,
                                      style: const TextStyle(
                                        color: Color(0xff121B35),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            course['desc'] as String,
                            style: const TextStyle(
                              color: Color(0xff5A6E85),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 6,
                                    backgroundColor: Colors.grey.shade100,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xff27C7D9)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "${(progress * 100).toInt()}%",
                                style: const TextStyle(
                                  color: Color(0xff121B35),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String _userName = 'Usuario';
  String _userAvatar = '';
  String _userStatus = 'offline';
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final auth = AuthService();
      final user = await auth.getCurrentUser();
      if (user != null) {
        _userId = user.$id;
        final profile = await auth.getUserProfile(user.$id);
        if (profile != null && mounted) {
          setState(() {
            _userName = profile['name'] ?? user.name;
            _userAvatar = profile['avatar'] ?? '';
            _userStatus = profile['status'] ?? 'offline';
          });
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            // User Header Info
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ).then((_) => _loadProfile());
              },
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xffCDEFF7),
                        backgroundImage: _userAvatar.isNotEmpty ? NetworkImage(_userAvatar) : null,
                        onBackgroundImageError: _userAvatar.isNotEmpty ? (_, __) {} : null,
                        child: _userAvatar.isEmpty
                            ? Text(
                                _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Color(0xff121B35)),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: _userStatus == 'online' ? const Color(0xff2ECC71) : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName,
                          style: const TextStyle(
                            color: Color(0xff121B35),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (_userStatus == 'online' ? const Color(0xff2ECC71) : Colors.grey).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 3,
                                backgroundColor: _userStatus == 'online' ? const Color(0xff2ECC71) : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _userStatus == 'online' ? 'En línea' : 'Desconectado',
                                style: TextStyle(
                                  color: _userStatus == 'online' ? const Color(0xff2ECC71) : Colors.grey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xffA8B8C0), size: 28),
                ],
              ),
            ),
            const SizedBox(height: 30),

            _buildSectionHeader("MI CUENTA"),
            _buildSettingsItem(
              icon: Icons.person_outline_rounded,
              title: "Mi Perfil",
              subtitle: "Editar nombre, foto y más",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ).then((_) => _loadProfile());
              },
            ),

            const SizedBox(height: 20),
            _buildSectionHeader("AJUSTES DE TRADUCCIÓN"),
            _buildSettingsItem(
              icon: Icons.subtitles_rounded,
              title: "Subtítulos automáticos",
              trailing: Switch(value: true, onChanged: (_) {}, activeThumbColor: const Color(0xff37C8F2), activeTrackColor: const Color(0xff37C8F2).withValues(alpha: 0.3)),
            ),
            _buildSettingsItem(
              icon: Icons.record_voice_over_rounded,
              title: "Voz de lectura LSB",
              subtitle: "Femenina (Bolivia)",
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.speed_rounded,
              title: "Velocidad de reconocimiento",
              subtitle: "Normal (1.0x)",
              onTap: () {},
            ),

            const SizedBox(height: 20),
            _buildSectionHeader("PREFERENCIAS GENERALES"),
            _buildSettingsItem(
              icon: Icons.dark_mode_rounded,
              title: "Modo Oscuro",
              trailing: Switch(value: true, onChanged: (_) {}, activeThumbColor: const Color(0xff37C8F2), activeTrackColor: const Color(0xff37C8F2).withValues(alpha: 0.3)),
            ),
            _buildSettingsItem(
              icon: Icons.language_rounded,
              title: "Idioma de la interfaz",
              subtitle: "Español",
              onTap: () {},
            ),

            const SizedBox(height: 30),
            // Logout
            ElevatedButton.icon(
              onPressed: () async {
                final auth = AuthService();
                if (_userId.isNotEmpty) {
                  await auth.setOnlineStatus(_userId, false);
                }
                await auth.logout();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xffEA2027).withValues(alpha: 0.15),
                foregroundColor: const Color(0xffEA2027),
                elevation: 0,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xffEA2027), width: 1),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text(
                "Cerrar Sesión",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Color(0xff5A6E85),
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xffE5F7FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xff27C7D9), size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Color(0xff121B35), fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(color: Color(0xffA8B8C0), fontSize: 12))
            : null,
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xffA8B8C0), size: 14)
                : null),
      ),
    );
  }
}
