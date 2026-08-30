import 'package:flutter/material.dart';

/// Identidade visual da OP OutSourcing usada no protótipo clicável:
/// fundo laranja/vermelho, ícones quase-preto, texto branco.
class AppColors {
  AppColors._();

  static const primary = Color(0xFFE7502E); // laranja/vermelho da marca
  static const primaryDark = Color(0xFFE74B32);
  static const ink = Color(0xFF241512); // quase-preto usado nos ícones/texto
  static const background = Color(0xFFF7F5F4);
  static const surface = Colors.white;
  static const success = Color(0xFF2E9E5B);
  static const warning = Color(0xFFC98A1B);
  static const danger = Color(0xFFC0392B);
  static const muted = Color(0xFF8A7B76);

  /// Gradiente usado nos cabeçalhos decorativos de Boas-vindas/Login/
  /// Cadastro (ver widgets/decorative_header.dart) — mesmo desenho do
  /// app Resenha, só que nas cores da marca OP OutSourcing em vez de azul.
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // Os FABs de "+" já existentes (novo cliente, novo compromisso...)
      // passam a usar esse quadrado arredondado escuro em vez do círculo
      // padrão do Material — mesmo visual do FAB do app Resenha, na cor
      // "quase-preto" que já era usada nos ícones/textos daqui.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.primary : AppColors.muted);
        }),
      ),
    );
  }
}
