import 'package:flutter/material.dart';

/// Tokens de color de Conecta. Única fuente de verdad: no usar `Color(0x…)`
/// sueltos en las pantallas.
///
/// Contraste (WCAG 2.1, AA pide 4.5:1 para texto normal):
/// - blanco sobre [brand]            → 4.9:1 ✓ (antes #27C7D9: 2.1:1 ✗)
/// - [ink] sobre [surface]           → 16:1  ✓
/// - [inkMuted] sobre blanco         → 7.0:1 ✓
/// - [brandBright] sobre [callBg]    → 8.7:1 ✓ (pantallas oscuras / video)
/// - [brand] sobre [brandSoft] da 4.3:1 ✗ → sobre brandSoft usar [ink].
class AppColors {
  AppColors._();

  /// Cyan profundo: fondos con texto blanco, texto/íconos sobre claro.
  static const brand = Color(0xff0E7C8C);

  /// Cyan brillante de la marca: solo sobre fondos oscuros o como acento
  /// con texto oscuro encima ([onBrandBright]).
  static const brandBright = Color(0xff27C7D9);
  static const onBrandBright = Color(0xff06222A);

  /// Relleno suave de marca (chips, burbujas propias, selección).
  static const brandSoft = Color(0xffDDF4F7);

  static const ink = Color(0xff0F1B2D);
  static const inkMuted = Color(0xff4A5B6E);
  static const surface = Color(0xffF4F9FB);
  static const surfaceCard = Colors.white;
  static const border = Color(0xffD5E3EA);

  /// Verde para "manos detectadas" / "seña reconocida".
  static const success = Color(0xff1B7F47); // sobre claro, texto blanco ✓
  static const successBright = Color(0xff2ECC71); // sobre oscuro
  static const danger = Color(0xffC62828);
  static const warning = Color(0xff8A5A00);

  /// Fondo de videollamada y cámara.
  static const callBg = Color(0xff0F172A);
  static const callSurface = Color(0xff1E293B);
}

/// Espaciados en múltiplos de 4.
class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  AppRadius._();
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

/// Tamaño mínimo de toque: 48 dp (Material) — el diseño del proyecto
/// pide 56 dp en acciones principales.
const double kMinTouch = 48;
const double kMainTouch = 56;

class AppTheme {
  AppTheme._();

  static const _font = 'AtkinsonHyperlegible';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      onPrimary: Colors.white,
      secondary: AppColors.brandBright,
      onSecondary: AppColors.onBrandBright,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      outline: AppColors.border,
      error: AppColors.danger,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.dark,
      primary: AppColors.brandBright,
      onPrimary: AppColors.onBrandBright,
      secondary: AppColors.brandBright,
      surface: AppColors.callBg,
      onSurface: const Color(0xffE6EEF3),
      onSurfaceVariant: const Color(0xffA9BBC8),
      outline: const Color(0xff33445A),
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    final text =
        Typography.material2021(platform: TargetPlatform.android).black.apply(
              fontFamily: _font,
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _font,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.brightness == Brightness.light
            ? AppColors.brand
            : AppColors.callSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.brightness == Brightness.light
            ? Colors.white
            : AppColors.callSurface,
        indicatorColor: scheme.brightness == Brightness.light
            ? AppColors.brandSoft
            : AppColors.brand,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 26,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: scheme.brightness == Brightness.light
            ? AppColors.surfaceCard
            : AppColors.callSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(kMinTouch, kMainTouch),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(kMinTouch, kMainTouch),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(kMinTouch, kMainTouch),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.5),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(kMinTouch, kMinTouch),
          foregroundColor: scheme.primary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.brightness == Brightness.light
            ? Colors.white
            : AppColors.callSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.brightness == Brightness.light
            ? AppColors.brandSoft
            : AppColors.callSurface,
        labelStyle: TextStyle(
          fontFamily: _font,
          color: scheme.brightness == Brightness.light
              ? AppColors.ink
              : Colors.white,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: _font,
          color: Colors.white,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline, space: 1),
    );
  }
}
