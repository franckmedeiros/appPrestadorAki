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
        // CORREÇÃO NA RAIZ do fundo rosado que o Franck apontou nos
        // diálogos ("essa cor não combina com o restante do app").
        //
        // `ColorScheme.fromSeed` deriva do laranja da marca uma família
        // inteira de tons de superfície (`surfaceContainer*`), e é ela
        // que o Material 3 usa como fundo de tudo que "flutua": diálogos,
        // menus, folhas que sobem de baixo, seletores de data e hora,
        // chips. Derivados de laranja, esses tons saem rosados — daí o
        // diálogo "Sair da conta?" destoar do branco dos cards.
        //
        // Fixando esses papéis em tons neutros aqui, a correção vale pro
        // app INTEIRO de uma vez, inclusive pras telas que ainda nem
        // existem, em vez de ter que caçar componente por componente.
        // (Os temas específicos mais abaixo continuam, deixando a
        // intenção explícita e cuidando de forma/tipografia.)
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: AppColors.surface,
        surfaceContainerHigh: AppColors.surface,
        surfaceContainerHighest: AppColors.background,
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
      // Diálogos (ex.: "Sair da conta?", "Excluir sua conta?") nasciam
      // com um fundo ROSADO que destoava do resto do app — o Franck
      // reparou. Não era cor escolhida por ninguém: o Material 3 pinta as
      // superfícies elevadas (diálogo, menu, folha que sobe de baixo)
      // misturando um pouco da cor da marca por cima do branco — é o
      // "surface tint". Com o laranja da marca, essa mistura dá rosa.
      //
      // `surfaceTintColor: Colors.transparent` desliga a mistura, e o
      // fundo branco explícito casa com o dos cards. Feito aqui no tema,
      // não em cada `showDialog`, pra valer pra todos os diálogos do app
      // de uma vez — inclusive os que ainda nem existem.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink),
      ),
      // Mesmo tingimento, mesmo ajuste: as folhas que sobem de baixo
      // (seletor de cidade, "Também quero oferecer serviços", detalhes do
      // orçamento) e os menus suspensos (arquivar/desarquivar) puxavam
      // pro rosa pela mesma razão.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // As mensagens que sobem no rodapé (avisos de erro, "Avaliação
      // registrada", "Conta criada"...) vinham num tom escuro
      // amarronzado, também derivado do laranja da marca. Agora usam o
      // "quase-preto" que já é a cor de texto do app, com as mesmas
      // bordas arredondadas do resto — flutuando, em vez de coladas na
      // borda inferior, pra não brigar com a barra de navegação.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        actionTextColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
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
