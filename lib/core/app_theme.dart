import 'package:flutter/material.dart';

/// Identidade visual do PrestadorAki.
///
/// As cores e medidas daqui vieram do guia de entrega do Figma
/// (set/2026) e substituíram a paleta laranja/clara que o app usava
/// desde o protótipo. O ponto da mudança não foi "trocar de laranja":
/// foi tirar a cor de marca de onde ela não precisa estar. Antes o
/// laranja pintava a barra de cima inteira em todas as telas, o que
/// dava ao app um ar de protótipo e deixava a cor sem força — quando
/// tudo é destaque, nada é. Agora o topo é carvão, o fundo é um creme
/// quente, e o laranja fica reservado pro que a pessoa deve TOCAR.
///
/// A cor velha ficou em `lib/core/app_theme.dart.bak_laranja` até o
/// Franck aprovar o visual novo no aparelho.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------
  // Paleta do guia
  // ---------------------------------------------------------------

  /// Ação principal: botões, links, aba ativa, valores em destaque.
  /// É a ÚNICA cor saturada do app — usar em outro lugar enfraquece ela.
  static const primary = Color(0xFFC6411C);

  /// Tom mais fechado do laranja — a caixinha da seta dentro do botão
  /// principal e o estado pressionado. Medido direto da tela do Figma.
  static const primaryProfundo = Color(0xFFAD3918);

  /// Bege do disco que fica atrás do logo nas telas de entrada.
  static const medalhao = Color(0xFFEAE6DE);

  /// Fim escuro do gradiente dos botões. Quase não se vê como cor
  /// separada; existe pra dar volume ao botão sem sombra colorida.
  static const primaryDark = Color(0xFFA93615);

  /// Laranja claro, pra usar SOBRE fundo escuro (no carvão do
  /// cabeçalho o `primary` fica ilegível — tem contraste de menos).
  static const primarySobreEscuro = Color(0xFFFF784A);

  /// Carvão: cor de todo texto principal e dos ícones.
  static const ink = Color(0xFF242624);

  /// Carvão mais profundo e mais quente — cabeçalhos, barra de cima e
  /// os blocos de módulo/ícone. É ele que dá a seriedade do visual novo.
  static const inkProfundo = Color(0xFF29231F);

  /// Fundo das telas: creme quente, não cinza. É o que faz os cartões
  /// brancos aparecerem sem precisar de borda nem sombra.
  static const background = Color(0xFFF5F2EB);

  /// Superfície dos cartões, campos, diálogos.
  static const surface = Colors.white;

  /// Texto secundário: descrições, legendas, rótulos de apoio.
  static const muted = Color(0xFF696C65);

  /// Texto de apoio DENTRO do cabeçalho escuro (o `muted` some ali).
  static const mutedSobreEscuro = Color(0xFFC4C7BC);

  /// Linhas: bordas de campo, divisórias, contorno de cartão quando
  /// precisa de um.
  static const borda = Color(0xFFDCDDD4);

  /// Fundo de realce na cor da marca — aba selecionada, chip ativo,
  /// faixa de aviso. Bem claro de propósito: é fundo, não é botão.
  static const primarySuave = Color(0xFFFBE6DA);

  // Estados. Cada um vem em par: a cor do texto e o fundo onde ele
  // é escrito — foi assim que o guia entregou, e é o que garante que
  // o selo "Pago" tenha contraste de verdade em vez de verde sobre
  // verde.
  static const success = Color(0xFF25664E);
  static const successSuave = Color(0xFFE3EEE6);
  static const warning = Color(0xFF896019);
  static const warningSuave = Color(0xFFF7EDCC);
  static const danger = Color(0xFFB3261E);
  static const dangerSuave = Color(0xFFFBE7E5);

  // ---------------------------------------------------------------
  // Gradientes
  // ---------------------------------------------------------------

  /// Gradiente laranja — SÓ pra botão principal (`GradientPillButton`).
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  /// Gradiente do cabeçalho e dos fundos de marca (splash, boas-vindas,
  /// topo de Login/Cadastro/Perfil). Era laranja; virou carvão.
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [inkProfundo, ink],
  );
}

/// Medidas do guia, num lugar só.
///
/// Estão aqui como constantes — e não espalhadas em cada tela — porque
/// a maior parte do "ar de app caseiro" vem de alturas e cantos que não
/// batem entre uma tela e outra: um botão de 48 aqui, um de 52 ali.
class AppMetrics {
  AppMetrics._();

  /// Altura de botão e de campo de texto. A mesma pros dois de
  /// propósito: botão embaixo de campo tem que alinhar.
  static const double alturaDeControle = 56;

  /// Altura da área de toque de uma ação escrita (um "Esqueci minha
  /// senha"). Menor que um botão, mas nunca menor que isso — abaixo de
  /// 44 o dedo erra.
  static const double alturaDeAcaoTextual = 44;

  static const double raioDeCartao = 12;
  static const double raioDeControle = 8;

  /// Margem lateral das telas. 402 de largura - 24 de cada lado = 354
  /// de conteúdo, que é a conta do guia.
  static const double margemLateral = 24;

  /// Respiro entre blocos de uma tela.
  static const double espacoEntreBlocos = 22;

  /// Respiro entre itens dentro de um cartão.
  static const double espacoInterno = 12;

  static const double paddingDeCartao = 16;

  /// Altura da barra de navegação de baixo.
  static const double alturaDaNavegacao = 68;
}

class AppTheme {
  AppTheme._();

  /// Escala tipográfica do guia.
  ///
  /// O app NÃO tinha nenhum tamanho de fonte definido no tema — cada
  /// tela escrevia o seu na mão. Isso é o que fazia dois títulos de
  /// seção saírem com tamanhos diferentes em telas vizinhas. Definindo
  /// aqui, toda tela que não mandar tamanho explícito já nasce certa;
  /// as que mandam continuam mandando (e vão sendo ajustadas aos
  /// poucos, tela por tela).
  static const _textTheme = TextTheme(
    // Cabeçalho grande das telas de entrada.
    headlineLarge: TextStyle(
      fontSize: 36,
      height: 1.06,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      height: 1.1,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    ),
    // Nome de pessoa, de serviço, de cartão.
    titleMedium: TextStyle(
      fontSize: 16,
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    // Título de seção.
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    // Texto corrido.
    bodyLarge: TextStyle(
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppColors.ink,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppColors.ink,
    ),
    // Descrição, legenda.
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppColors.muted,
    ),
    // Rótulo de botão.
    labelLarge: TextStyle(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
    // Rótulo de campo.
    labelMedium: TextStyle(
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    // Selo/badge.
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.inkProfundo,
        onSecondary: Colors.white,
        error: AppColors.danger,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        outline: AppColors.borda,
        outlineVariant: AppColors.borda,
        // CORREÇÃO NA RAIZ do fundo rosado que o Franck apontou nos
        // diálogos ("essa cor não combina com o restante do app").
        //
        // `ColorScheme.fromSeed` deriva da cor de marca uma família
        // inteira de tons de superfície (`surfaceContainer*`), e é ela
        // que o Material 3 usa como fundo de tudo que "flutua": diálogos,
        // menus, folhas que sobem de baixo, seletores de data e hora,
        // chips. Derivados de laranja, esses tons saem rosados — daí o
        // diálogo "Sair da conta?" destoar do branco dos cards.
        //
        // Fixando esses papéis em tons neutros aqui, a correção vale pro
        // app INTEIRO de uma vez, inclusive pras telas que ainda nem
        // existem, em vez de ter que caçar componente por componente.
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: AppColors.surface,
        surfaceContainerHigh: AppColors.surface,
        surfaceContainerHighest: AppColors.background,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: _textTheme,
    );

    return base.copyWith(
      // A barra de cima deixou de ser uma faixa colorida. Nas telas do
      // Figma não existe barra nenhuma: o topo é o mesmo creme do resto
      // da tela, com a marca de um lado e a área (cliente/prestador) do
      // outro — ver widgets/cabecalho_de_tela.dart. Esta AppBarTheme
      // atende as telas que ainda usam uma `AppBar` comum (diálogos de
      // seleção, telas internas), pra elas não destoarem enquanto não
      // forem convertidas.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        iconTheme: IconThemeData(color: AppColors.ink),
      ),
      iconTheme: const IconThemeData(color: AppColors.ink),
      dividerTheme: const DividerThemeData(
        color: AppColors.borda,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borda,
          disabledForegroundColor: AppColors.muted,
          elevation: 0,
          minimumSize: const Size.fromHeight(AppMetrics.alturaDeControle),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          textStyle: const TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(AppMetrics.alturaDeControle),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          side: const BorderSide(color: AppColors.borda),
          textStyle: const TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, AppMetrics.alturaDeAcaoTextual),
          textStyle: const TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        // 56 de altura é a conta do guia: 14 de padding em cima e
        // embaixo + a linha de texto. `isDense: false` + esse padding
        // chega lá sem precisar embrulhar o campo num SizedBox.
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          borderSide: const BorderSide(color: AppColors.borda),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          borderSide: const BorderSide(color: AppColors.borda),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        // A borda fininha não é enfeite: o fundo das telas é creme e o
        // cartão é branco, e a diferença entre os dois é pequena demais
        // pra separar sozinha. Era isso ou sombra — e sombra sobre creme
        // fica suja.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
          side: const BorderSide(color: AppColors.borda),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primarySuave,
        side: const BorderSide(color: AppColors.borda),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeControle),
        ),
      ),
      // Diálogos (ex.: "Sair da conta?", "Excluir sua conta?") nasciam
      // com um fundo ROSADO que destoava do resto do app — o Franck
      // reparou. Não era cor escolhida por ninguém: o Material 3 pinta as
      // superfícies elevadas misturando um pouco da cor da marca por cima
      // do branco. `surfaceTintColor: Colors.transparent` desliga isso.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          height: 1.45,
          color: AppColors.ink,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.inkProfundo,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        actionTextColor: AppColors.primarySobreEscuro,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
        ),
        elevation: 3,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.raioDeCartao),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        height: AppMetrics.alturaDaNavegacao,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        // Sem a "pílula" do Material atrás do ícone selecionado: no
        // desenho do Figma o item ativo é só o laranja do ícone e do
        // rótulo. A pílula engordava a barra e brigava com o fundo
        // branco dela.
        indicatorColor: Colors.transparent,
        indicatorShape: const RoundedRectangleBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? AppColors.primary : AppColors.muted,
          );
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.primary,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}
