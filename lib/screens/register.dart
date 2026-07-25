import 'package:flutter/material.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/screens/chat.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  bool _isLoading = false;

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
    _nameController.dispose();
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

  Future<void> _onRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final localDigits =
          _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final fullPhone = '$_selectedCountryCode$localDigits';

      await _authService.register(
        name: _nameController.text.trim(),
        phone: fullPhone,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChatScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F9FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.10),
                            blurRadius: 30,
                            offset: const Offset(0, 10))
                      ],
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      size: 50,
                      color: Color(0xff37C8F2),
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "Crear Cuenta",
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff222222)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Solo necesitas tu nombre y teléfono",
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                  const SizedBox(height: 35),

                  _buildTextField(
                    controller: _nameController,
                    hint: "Nombre completo",
                    icon: Icons.person_outline_rounded,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Ingresa tu nombre'
                        : null,
                  ),
                  const SizedBox(height: 16),

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
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                                Icon(Icons.arrow_drop_down,
                                    color: Colors.grey.shade600, size: 20),
                              ],
                            ),
                          ),
                        ),
                        Container(
                            width: 1, height: 30, color: Colors.grey.shade300),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Ingresa tu número';
                              }
                              if (v.trim().length < 8) {
                                return 'Mínimo 8 dígitos';
                              }
                              return null;
                            },
                            style: const TextStyle(fontSize: 16),
                            decoration: const InputDecoration(
                              hintText: "Número de teléfono",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 18, horizontal: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _onRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff37C8F2),
                        disabledBackgroundColor:
                            const Color(0xff37C8F2).withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text(
                              "Crear Cuenta",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("¿Ya tienes cuenta? ",
                          style: TextStyle(color: Colors.grey)),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text("Iniciar Sesión",
                            style: TextStyle(
                                color: Color(0xff37C8F2),
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Container(
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
      child: TextFormField(
        controller: controller,
        validator: validator,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xff37C8F2)),
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}
