import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:conecta_lsb/theme/app_theme.dart';

/// Ilustraciones (unDraw, recoloreadas al cyan de marca).
class Illustrations {
  Illustrations._();
  static const chatsEmpty = 'assets/illustrations/chats_empty.svg';
  static const contactsEmpty = 'assets/illustrations/contacts_empty.svg';
  static const welcome = 'assets/illustrations/welcome.svg';
  static const cameraPermission = 'assets/illustrations/camera_permission.svg';
  static const connectionLost = 'assets/illustrations/connection_lost.svg';
  static const callWaiting = 'assets/illustrations/call_waiting.svg';
}

/// Estado vacío: una invitación, no una disculpa. Ilustración + título +
/// una línea que explica + acción con verbo.
class EmptyState extends StatelessWidget {
  final String illustration;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool dark;

  const EmptyState({
    super.key,
    required this.illustration,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decorativa: el título ya describe el estado.
              ExcludeSemantics(
                child: SvgPicture.asset(illustration, height: 160),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white : AppColors.ink,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(
                  color: dark ? Colors.white70 : AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpace.xl),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? Icons.add_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tres puntos animados: "escribiendo…" / "haciendo señas…".
class TypingDots extends StatefulWidget {
  final Color color;
  final double size;
  const TypingDots({super.key, this.color = AppColors.inkMuted, this.size = 8});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          // Cada punto sube con desfase; sin animación si el sistema lo pide.
          final phase = ((_c.value - i * 0.18) % 1.0);
          final lift = reduce ? 0.0 : (phase < 0.5 ? phase : 1 - phase) * 2;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.size * 0.25),
            child: Transform.translate(
              offset: Offset(0, -lift * widget.size * 0.6),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.45 + 0.55 * lift),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Burbuja "está escribiendo / haciendo señas" para el chat.
class TypingBubble extends StatelessWidget {
  final String label;
  const TypingBubble({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TypingDots(),
            const SizedBox(width: AppSpace.sm),
            Text(
              label,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Canal por el que llegó un mensaje: la persona sorda necesita saber si
/// el texto viene de señas, de voz transcrita o fue escrito.
enum MessageChannel { sign, voice, text }

class ChannelTag extends StatelessWidget {
  final MessageChannel channel;
  final bool onDark;
  const ChannelTag({super.key, required this.channel, this.onDark = false});

  static (IconData, String) describe(MessageChannel c) => switch (c) {
        MessageChannel.sign => (Icons.sign_language_rounded, 'Señas'),
        MessageChannel.voice => (Icons.mic_rounded, 'Voz'),
        MessageChannel.text => (Icons.keyboard_rounded, 'Texto'),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, label) = describe(channel);
    final color = onDark ? Colors.white70 : AppColors.inkMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Confirmación de "seña reconocida": destello verde en el borde + vibración.
/// La persona sorda no oye el TTS, así que la confirmación debe ser visual
/// y háptica.
class SignFlash extends StatefulWidget {
  final Widget child;

  /// Cambia cada vez que se reconoce una seña (p. ej. un contador).
  final Object? trigger;
  final double radius;

  const SignFlash({
    super.key,
    required this.child,
    required this.trigger,
    this.radius = AppRadius.lg,
  });

  @override
  State<SignFlash> createState() => _SignFlashState();
}

class _SignFlashState extends State<SignFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void didUpdateWidget(SignFlash old) {
    super.didUpdateWidget(old);
    if (widget.trigger != null && widget.trigger != old.trigger) {
      HapticFeedback.mediumImpact();
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final a = _c.isAnimating ? (1 - _c.value) : 0.0;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: AppColors.successBright.withValues(alpha: a),
              width: 4,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
