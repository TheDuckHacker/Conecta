import 'package:flutter/material.dart';
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

/// Asistente de Conecta LSB (chat en la app).
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
            'Hola, soy el asistente de Conecta LSB. '
            'Te ayudo con las señas de la guía (Hola, ¿Cómo estás?, Yo, Bien, Sí, No), '
            'Academia, Traducción y videollamadas.',
        fromUser: false,
        source: 'conecta',
      ),
    );
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
        _messages.add(
          _Bubble(text: out.reply, fromUser: false, source: out.source),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _Bubble(
            text:
                'No pude contactar al servidor. Revisa tu internet. '
                'Mientras: Academia → Cómo empezar muestra los pasos de cada seña.',
            fromUser: false,
            source: 'local',
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
              'Asistente Conecta',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Señas, Academia y llamadas',
              style: TextStyle(fontSize: 12, color: Color(0xff5A6E85)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i];
                final align =
                    m.fromUser ? Alignment.centerRight : Alignment.centerLeft;
                final bg =
                    m.fromUser ? const Color(0xff27C7D9) : Colors.white;
                final fg =
                    m.fromUser ? Colors.white : const Color(0xff121B35);
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
                    child: Text(
                      m.text,
                      style: TextStyle(color: fg, height: 1.35, fontSize: 15),
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
                        hintText: 'Escribe tu duda aquí…',
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
