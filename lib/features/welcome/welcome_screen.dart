import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../widgets/botao_com_seta.dart';
import '../../widgets/marca_app.dart';

/// Tela de boas-vindas antes do login — primeira coisa que um prestador
/// sem sessão salva vê.
///
/// Redesenhada a partir da entrega do Figma (out/2026). O que mudou em
/// relação ao desenho antigo, e por quê:
///
///  - O fundo deixou de ser um gradiente laranja de tela cheia. Uma cor
///    forte ocupando tudo não deixa nada se destacar — os dois botões
///    tinham que virar branco e contorno branco pra aparecer, e aí os
///    dois pareciam igualmente importantes. No creme, o "Entrar" laranja
///    é a única coisa colorida da tela, e a hierarquia se resolve sozinha.
///  - O nome do app saiu do meio (abaixo do logo, em caixa alta e branco)
///    e foi pro canto superior esquerdo, pequeno. Quem abre o app sabe
///    qual app abriu; o meio da tela é melhor gasto com a frase que
///    explica pra que ele serve.
///
/// Também é o que a aba "Perfil" mostra pra quem ainda não tem conta (ver
/// UserProfileScreen) — ali o "Entrar" leva pras sub-rotas do próprio
/// branch, pra tela abrir DENTRO da casca do app, com a barra de
/// navegação embaixo (pedido do Franck: "precisa ficar dentro do espaço
/// e não fora assim").
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    this.rotaEntrar = '/login',
    this.rotaCriarConta = '/register',
  });

  final String rotaEntrar;
  final String rotaCriarConta;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, limites) {
            return SingleChildScrollView(
              // Em tela baixa o conteúdo rola; em tela normal ele se
              // espalha pela altura toda (é o `minHeight` + o `Spacer`
              // lá embaixo que fazem isso). Sem isso, ou a tela estoura
              // nos aparelhos pequenos, ou fica tudo amontoado no topo
              // nos grandes.
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: limites.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.margemLateral,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      const TopoDeEntrada(etiqueta: 'Bem-vindo!'),
                      const SizedBox(height: 28),
                      const Center(child: MedalhaoDaMarca()),
                      const SizedBox(height: 36),
                      const TituloDeEntrada('Tudo em um só lugar'),
                      const SizedBox(height: 14),
                      const Text(
                        'Do primeiro orçamento até você chegar à porta do '
                        'cliente — tudo em um só lugar.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Divider(color: AppColors.borda, height: 1),
                      const Spacer(),
                      const SizedBox(height: 28),
                      BotaoComSeta(
                        rotulo: 'Entrar',
                        aoTocar: () => context.push(rotaEntrar),
                      ),
                      const SizedBox(height: 12),
                      BotaoComSeta(
                        rotulo: 'Criar conta',
                        preenchido: false,
                        aoTocar: () => context.push(rotaCriarConta),
                      ),
                      const SizedBox(height: 10),
                      // Buscar prestador nunca exige conta — quem chegou
                      // aqui sem querer volta direto pra busca.
                      TextButton.icon(
                        onPressed: () => context.go('/buscar'),
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Só quero buscar um prestador'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
