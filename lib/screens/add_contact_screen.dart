import 'package:flutter/material.dart';
import 'package:appwrite/models.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/contact_service.dart';
import 'package:conecta_lsb/screens/chat_detail.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _phoneController = TextEditingController();
  final _contactService = ContactService();
  final _authService = AuthService();

  bool _isSearching = false;
  bool _isAdding = false;
  Document? _foundUser;
  String _errorMessage = '';

  String _selectedCountryCode = '+591';
  String _selectedFlag = '🇧🇴';

  final List<Map<String, String>> _countries = [
    {'code': '+51', 'flag': '🇵🇪', 'name': 'Perú'},
    {'code': '+591', 'flag': '🇧🇴', 'name': 'Bolivia'},
    {'code': '+56', 'flag': '🇨🇱', 'name': 'Chile'},
    {'code': '+54', 'flag': '🇦🇷', 'name': 'Argentina'},
    {'code': '+57', 'flag': '🇨🇴', 'name': 'Colombia'},
    {'code': '+593', 'flag': '🇪🇨', 'name': 'Ecuador'},
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text("Seleccionar país",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._countries.map((country) {
                final isSelected = country['code'] == _selectedCountryCode;
                return ListTile(
                  leading: Text(country['flag']!,
                      style: const TextStyle(fontSize: 28)),
                  title: Text(
                    "${country['name']}  (${country['code']})",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xff37C8F2))
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedCountryCode = country['code']!;
                      _selectedFlag = country['flag']!;
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _searchContact() async {
    final text = _phoneController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = '';
      _foundUser = null;
    });

    final localDigits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final fullPhone = '$_selectedCountryCode$localDigits';

    try {
      final user = await _contactService.searchUserByPhone(fullPhone);
      final currentUser = await _authService.getCurrentUser();

      if (!mounted) return;

      if (user == null) {
        setState(() {
          _errorMessage = 'No se encontró ningún usuario con ese número.';
        });
      } else if (currentUser != null && user.$id == currentUser.$id) {
        setState(() {
          _errorMessage = 'No puedes agregarte a ti mismo como contacto.';
        });
      } else {
        setState(() {
          _foundUser = user;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error buscando contacto: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addContact() async {
    if (_foundUser == null) return;

    setState(() => _isAdding = true);

    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) return;

      final localDigits =
          _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
      final fullPhone = '$_selectedCountryCode$localDigits';

      await _contactService.addContact(
        userId: currentUser.$id,
        contactUserId: _foundUser!.$id,
        phone: fullPhone,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacto agregado exitosamente'),
            backgroundColor: Color(0xff37C8F2),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _startDirectChat() async {
    if (_foundUser == null) return;
    final currentUser = await _authService.getCurrentUser();
    if (currentUser == null) return;

    try {
      // Guardar como contacto y abrir chat
      final localDigits =
          _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
      final fullPhone = '$_selectedCountryCode$localDigits';

      final chat = await _contactService.addContact(
        userId: currentUser.$id,
        contactUserId: _foundUser!.$id,
        phone: fullPhone,
      );

      final isOnline = (_foundUser!.data['status'] ?? '') == 'online';

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              chatId: chat.$id,
              name: _foundUser!.data['name'] ?? 'Usuario',
              avatar: _foundUser!.data['avatar'] ?? '',
              isActive: isOnline,
              currentUserId: currentUser.$id,
              otherUserId: _foundUser!.$id,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xff37C8F2);

    return Scaffold(
      backgroundColor: const Color(0xffF5F9FC),
      appBar: AppBar(
        title: const Text('Agregar Contacto',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: accent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Buscar por número de teléfono",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff1A3A4A)),
            ),
            const SizedBox(height: 6),
            const Text(
              "Ingresa el número de tu contacto para encontrarlo en Conecta.",
              style: TextStyle(fontSize: 14, color: Color(0xff6B9BB0)),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.10),
                      blurRadius: 15,
                      offset: const Offset(0, 5))
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showCountryPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Text(_selectedFlag,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 4),
                          Text(_selectedCountryCode,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                          Icon(Icons.arrow_drop_down,
                              color: Colors.grey.shade600, size: 20),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      onFieldSubmitted: (_) => _searchContact(),
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: "Número de teléfono",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 18, horizontal: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search_rounded, color: accent),
                    onPressed: _isSearching ? null : _searchContact,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_isSearching)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: accent),
              )),
            if (_errorMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                ),
              ),
            if (_foundUser != null) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xffCDEFF7),
                          backgroundImage:
                              (_foundUser!.data['avatar'] ?? '').isNotEmpty
                                  ? NetworkImage(_foundUser!.data['avatar'])
                                  : null,
                          child: (_foundUser!.data['avatar'] ?? '').isEmpty
                              ? Text(
                                  (_foundUser!.data['name'] ?? 'U')[0]
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _foundUser!.data['name'] ?? 'Sin nombre',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xff1A3A4A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _foundUser!.data['phone'] ?? '',
                                style: const TextStyle(
                                    color: Color(0xff6B9BB0), fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAdding ? null : _addContact,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: _isAdding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.person_add_rounded,
                                    color: Colors.white),
                            label: const Text(
                              "Agregar a contactos",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: _startDirectChat,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: accent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(14),
                          ),
                          child: const Icon(Icons.chat_bubble_rounded,
                              color: accent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
