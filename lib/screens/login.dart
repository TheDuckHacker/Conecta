import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/chat.dart';
import 'package:conecta_lsb/screens/register.dart';
import 'package:conecta_lsb/services/auth_service.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  bool _isLoading = false;

  // Flujo: false = ingresando teléfono, true = ingresando código OTP
  bool _otpSent = false;
  String? _userId;

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
    _otpController.dispose();
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

  /// Paso 1: Enviar código OTP
  Future<void> _onSendOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final localDigits =
          _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final fullPhone = '$_selectedCountryCode$localDigits';

      final userId = await _authService.sendOTP(phone: fullPhone);

      if (mounted) {
        setState(() {
          _otpSent = true;
          _userId = userId;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📩 Código enviado a tu teléfono'),
            backgroundColor: Color(0xff37C8F2),
          ),
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

  /// Paso 2: Verificar código OTP
  Future<void> _onVerifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa el código de 6 dígitos'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.verifyOTP(userId: _userId!, otp: otp);

      // Asegurar perfil en la DB
      final user = await _authService.getCurrentUser();
      if (user != null) {
        final localDigits =
            _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
        final fullPhone = '$_selectedCountryCode$localDigits';
        await _authService.ensureUserProfile(
          userId: user.$id,
          name: user.name.isNotEmpty ? user.name : 'Usuario',
          phone: fullPhone,
        );
      }

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

  void _onBack() {
    setState(() {
      _otpSent = false;
      _userId = null;
      _otpController.clear();
    });
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
                  const SizedBox(height: 60),
                  // Ícono
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.10),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Icon(
                      _otpSent ? Icons.sms_rounded : Icons.chat_bubble_rounded,
                      size: 55,
                      color: const Color(0xff37C8F2),
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text("CONECTA",
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff222222))),
                  const SizedBox(height: 10),
                  Text(
                    _otpSent ? "Verificación" : "Bienvenido",
                    style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff222222)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _otpSent
                        ? "Ingresa el código que recibiste por SMS"
                        : "Ingresa tu número para continuar.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 50),

                  // --- CAMPO TELÉFONO o CAMPO OTP ---
                  if (!_otpSent) ...[
                    // Campo de teléfono
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
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
                              width: 1,
                              height: 30,
                              color: Colors.grey.shade300),
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
                  ] else ...[
                    // Campo de código OTP
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
                      child: TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 12),
                        decoration: const InputDecoration(
                          hintText: "------",
                          hintStyle: TextStyle(
                              letterSpacing: 12, color: Colors.grey),
                          border: InputBorder.none,
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 18, horizontal: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Reenviar código
                    GestureDetector(
                      onTap: _isLoading ? null : _onSendOTP,
                      child: const Text(
                        "¿No recibiste el código? Reenviar",
                        style: TextStyle(
                            color: Color(0xff37C8F2),
                            fontWeight: FontWeight.w500,
                            fontSize: 14),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),

                  // Botón principal
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : (_otpSent ? _onVerifyOTP : _onSendOTP),
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
                          : Text(
                              _otpSent ? "Verificar Código" : "Enviar Código",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),

                  // Botón volver (si está en OTP)
                  if (_otpSent) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: _onBack,
                        child: const Text("← Cambiar número",
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("¿No tienes cuenta? ",
                          style: TextStyle(color: Colors.grey)),
                      GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RegisterScreen())),
                        child: const Text("Regístrate",
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
}
