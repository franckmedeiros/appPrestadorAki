import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/subscription_service.dart';

/// Tela de venda da assinatura mensal — único jeito de virar prestador
/// (aparecer na busca "Encontre um profissional"). Decisão combinada com
/// o Franck: nada de cobrança manual via Pix/cartão nem corte manual de
/// quem não pagar — tudo passa pelo Google Play Billing, com renovação e
/// cancelamento automáticos cuidados pela própria Play Store (ver
/// functions/src/subscription.ts).
///
/// Aberta a partir de `_BecomeProviderSheet` (UserProfileScreen), depois
/// que a pessoa já escolheu categoria/cidade/UF. Se a compra for
/// concluída e confirmada com sucesso pelo servidor, fecha sozinha
/// devolvendo `true` — quem chamou já pode tratar a conta como
/// prestador (ver `AuthController.refreshProviderStatus`).
class ProviderPaywallScreen extends StatefulWidget {
  const ProviderPaywallScreen({
    super.key,
    required this.category,
    required this.city,
    this.state,
  });

  final String category;
  final String city;
  final String? state;

  @override
  State<ProviderPaywallScreen> createState() => _ProviderPaywallScreenState();
}

class _ProviderPaywallScreenState extends State<ProviderPaywallScreen> {
  final _service = SubscriptionService.instance;
  ProductDetails? _produto;
  bool _carregandoProduto = true;
  bool _comprando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _service.iniciarEscuta(
      category: widget.category,
      city: widget.city,
      state: widget.state,
      onAtivada: () async {
        if (!mounted) return;
        await context.read<AuthController>().refreshProviderStatus();
        if (!mounted) return;
        setState(() => _comprando = false);
        Navigator.of(context).pop(true);
      },
      onErro: (mensagem) {
        if (!mounted) return;
        setState(() {
          _comprando = false;
          _erro = mensagem;
        });
      },
    );
    _carregarProduto();
  }

  @override
  void dispose() {
    _service.pararEscuta();
    super.dispose();
  }

  Future<void> _carregarProduto() async {
    setState(() {
      _carregandoProduto = true;
      _erro = null;
    });
    try {
      final disponivel = await _service.disponivel;
      if (!disponivel) {
        setState(() {
          _erro = 'Assinaturas ainda não estão disponíveis nesse aparelho.';
          _carregandoProduto = false;
        });
        return;
      }
      final resposta = await _service.buscarProduto();
      if (!mounted) return;
      setState(() {
        _produto = resposta.productDetails.isEmpty ? null : resposta.productDetails.first;
        if (_produto == null) {
          _erro = 'A assinatura ainda não está disponível pra compra — volte em breve.';
        }
        _carregandoProduto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'A assinatura ainda não está disponível pra compra — volte em breve.';
        _carregandoProduto = false;
      });
    }
  }

  Future<void> _assinar() async {
    final produto = _produto;
    if (produto == null) return;
    setState(() {
      _comprando = true;
      _erro = null;
    });
    try {
      await _service.comprar(produto);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comprando = false;
        _erro = _service.descreverErro(e);
      });
    }
  }

  Future<void> _restaurar() async {
    setState(() => _erro = null);
    try {
      await _service.restaurarCompras();
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _service.descreverErro(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Virar prestador')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.handyman_outlined, color: AppColors.primary, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Assine e apareça pros clientes',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sua conta continua a mesma — isso só adiciona a área de prestador.',
              style: TextStyle(color: AppColors.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 24),
            const _BeneficioItem(
              icon: Icons.search_outlined,
              texto: 'Apareça nas buscas dos clientes da sua cidade',
            ),
            const SizedBox(height: 14),
            const _BeneficioItem(
              icon: Icons.request_quote_outlined,
              texto: 'Receba pedidos de orçamento e monte sua agenda',
            ),
            const SizedBox(height: 14),
            const _BeneficioItem(
              icon: Icons.autorenew,
              texto: 'Renovação automática todo mês, cancele quando quiser',
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDDE4EE)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Plano mensal',
                    style: TextStyle(fontSize: 13.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _produto?.price ?? '...',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Renovação automática, cancele quando quiser na Play Store',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  if (_erro != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _erro!,
                              style: const TextStyle(color: AppColors.danger, fontSize: 12.5, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton(
                    onPressed: (_carregandoProduto || _comprando || _produto == null) ? null : _assinar,
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: _comprando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_carregandoProduto ? 'Carregando...' : 'Assinar'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _comprando ? null : _restaurar,
                    child: const Text('Já assinei, restaurar compra'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeneficioItem extends StatelessWidget {
  const _BeneficioItem({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.08),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}
