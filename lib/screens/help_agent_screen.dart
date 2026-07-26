import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:conecta_lsb/services/help_agent_service.dart';

class _Bubble {
  final String text;
  final bool fromUser;
  final String? source;

  const _Bubble({
    required this.text,
    required this.fromUser,
    this.source,
  });
}

/// Chat de ayuda in-app + puente a WhatsApp vía Zavu.
class HelpAgentScreen extends StatefulWidget {
  const HelpAgentScreen({super.key});

  @override
  State<HelpAgentScreen> createState() => _HelpAgentScreenState();
}

class _HelpAgentScreenState extends State<HelpAgentScreen> {
  final _agent = HelpAgentService.instance;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Bubble> _messages = [];
  bool _busy = false;
  ZavuStatus _zavu = const ZavuStatus(configured: false);

  static const _suggestions = [
    '¿Cómo hago la seña Hola?',
    '¿Cómo digo cómo estás?',
    '¿Cómo uso la Academia?',
    '¿Cómo funciona la Traducción?',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _Bubble(
        text:
            'Hola, soy el agente de ayuda de Conecta LSB. '
            'Pregúntame cómo hacer señas, usar Academia o Traducción. '
            'También puedes continuar por WhatsApp con Zavu.',
        fromUser: false,
        source: 'conecta',
      ),
    );
    _loadZavu();
  }

  Future<void> _loadZavu() async {
    try {
      final s = await _agent.zavuStatus();
      if (mounted) setState(() => _zavu = s);
    } catch (_) {}
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _messages.add(_Bubble(text: text, fromUser: true));
      _ctrl.clear();
    });
    _jumpBottom();
    try {
      final out = await _agent.ask(text);
      if (!mounted) return;
      setState(() {
        _zavu = ZavuStatus(
          configured: out.zavuConfigured,
          whatsappNumber: out.whatsappNumber.replaceAll(RegExp(r'\D'), ''),
          waMe: out.whatsappNumber.isNotEmpty
              ? 'https://wa.me/${out.whatsappNumber.replaceAll(RegExp(r'\D'), '')}'
              : _zavu.waMe,
        );
        _messages.add(
          _Bubble(text: out.reply, fromUser: false, source: out.source),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Bubble(
            text:
                'No pude contactar al servidor. Revisa tu internet. '
                'Mientras: Academia → Cómo empezar muestra los pasos de cada seña.\n($e)',
            fromUser: false,
            source: 'error',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _jumpBottom();
    }
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openWhatsApp() async {
    var wa = _zavu.waMe;
    if (wa.isEmpty && _zavu.whatsappNumber.isNotEmpty) {
      wa = 'https://wa.me/${_zavu.whatsappNumber}';
    }
    if (wa.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Zavu aún no tiene número en el servidor. '
            'Configura ZAVU_WHATSAPP_NUMBER en Render.',
          ),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      '$wa?text=${Uri.encodeComponent("Hola, necesito ayuda con Conecta LSB")}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  Future<void> _sendPhoneViaZavu() async {
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar por Zavu'),
        content: TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Tu WhatsApp (con código país)',
            hintText: '+59170000000',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    final to = phoneCtrl.text.trim();
    phoneCtrl.dispose();
    if (ok != true || to.isEmpty) return;

    final helpMsgs = _messages.where((m) => !m.fromUser).toList();
    final lastHelp =
        helpMsgs.isNotEmpty ? helpMsgs.last.text : null;
    final text = lastHelp ??
        'Hola desde Conecta LSB. Escribe tu duda y el agente Zavu te ayudará.';

    try {
      final sent = await _agent.sendViaZavu(to: to, text: text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Mensaje enviado por Zavu a $to'
                : 'No se pudo enviar (¿ZAVU_API_KEY en Render?)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error Zavu: $e')),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xff121B35),
        elevation: 0.5,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agente de ayuda',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Conecta + Zavu',
              style: TextStyle(fontSize: 12, color: Color(0xff5A6E85)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'WhatsApp (Zavu)',
            onPressed: _openWhatsApp,
            icon: const Icon(Icons.chat_rounded, color: Color(0xff25D366)),
          ),
          IconButton(
            tooltip: 'Enviar por API Zavu',
            onPressed: _sendPhoneViaZavu,
            icon: const Icon(Icons.send_to_mobile_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_zavu.configured || _zavu.whatsappNumber.isNotEmpty)
            Material(
              color: const Color(0xffE8F8EF),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle, color: Color(0xff25D366)),
                title: Text(
                  _zavu.configured
                      ? 'Zavu listo en el servidor'
                      : 'WhatsApp de ayuda disponible',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                trailing: TextButton(
                  onPressed: _openWhatsApp,
                  child: const Text('Abrir WhatsApp'),
                ),
              ),
            )
          else
            const Material(
              color: Color(0xffFFF6E5),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.info_outline, color: Colors.orange),
                title: Text(
                  'Chat in-app activo. Zavu/WhatsApp se activa con ZAVU_API_KEY en Render.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i];
                final align =
                    m.fromUser ? Alignment.centerRight : Alignment.centerLeft;
                final bg = m.fromUser
                    ? const Color(0xff27C7D9)
                    : Colors.white;
                final fg = m.fromUser ? Colors.white : const Color(0xff121B35);
                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.text,
                          style: TextStyle(color: fg, height: 1.35, fontSize: 15),
                        ),
                        if (!m.fromUser && m.source != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            m.source == 'gemini'
                                ? 'IA · servidor'
                                : (m.source == 'conecta'
                                    ? 'Conecta'
                                    : m.source!),
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.55),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final s = _suggestions[i];
                return ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: _busy ? null : () => _send(s),
                  backgroundColor: const Color(0xffE5F7FF),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Escribe tu duda…',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : () => _send(),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xff27C7D9),
                      foregroundColor: Colors.white,
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
