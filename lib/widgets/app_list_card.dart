import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Um número com ícone, exibido na fileira de estatísticas no rodapé de um
/// [AppListCard] (ex.: "5 participantes", "3 confirmados") — inspirado no
/// card de "Minhas resenhas" do app Resenha.
class AppListCardStat {
  const AppListCardStat({required this.icon, required this.value, this.color});

  final IconData icon;
  final String value;
  final Color? color;
}

/// Card de lista compartilhado pelo app inteiro (cliente e prestador) —
/// avatar à esquerda, título + subtítulo, algo à direita (seta, chip,
/// botão...) e, opcionalmente, uma fileira de estatísticas no rodapé.
/// Visual inspirado no card de "Minhas resenhas" do app Resenha, com a cor
/// de marca do PrestadorAki no lugar do azul original.
class AppListCard extends StatelessWidget {
  const AppListCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.footer,
    this.stats = const [],
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  // Conteúdo de largura livre abaixo do título/subtítulo (ex.: um selo de
  // status) — diferente de `stats`, que é a fileira de número+ícone com
  // divisória (ex.: "5 participantes"). Sem divisória, espaçamento mais
  // enxuto: pensado pra texto curto, não pra uma segunda seção do card.
  final Widget? footer;
  final List<AppListCardStat> stats;
  final VoidCallback? onTap;

  /// Avatar padrão: quadrado arredondado com o gradiente da marca — usado
  /// quando não faz sentido um avatar de iniciais (perfil de prestador,
  /// pedido do marketplace, categoria de serviço...).
  static Widget iconAvatar(IconData icon) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(color: AppColors.muted, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                ],
              ),
              if (footer != null) ...[
                const SizedBox(height: 8),
                footer!,
              ],
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final stat in stats) ...[
                      Icon(stat.icon, size: 16, color: stat.color ?? AppColors.muted),
                      const SizedBox(width: 4),
                      Text(
                        stat.value,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: stat.color ?? AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
