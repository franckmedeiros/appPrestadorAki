import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';

/// "Recebi um código no WhatsApp" — pré-cadastro com consentimento (ver
/// functions/src/convites.ts). O prestador que foi avisado de um pedido
/// digita o código: o servidor liga o perfil pré-cadastrado a esta conta e
/// traz os pedidos que estavam esperando. Depois disso a conta é prestador
/// (ainda sem assinatura), e o app leva pra tela de assinatura, que mostra
/// os pedidos esperando.
///
/// Devolve `true` se o perfil foi ativado.
Future<bool> abrirCodigoConvite(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _CodigoConviteDialog(),
  );
  if (ok == true && context.mounted) {
    await context.read<AuthController>().refreshProviderStatus();
  }
  return ok == true;
}

class _CodigoConviteDialog extends StatefulWidget {
  const _CodigoConviteDialog();

  @override
  State<_CodigoConviteDialog> createState() => _CodigoConviteDialogState();
}

class _CodigoConviteDialogState extends State<_CodigoConviteDialog> {
  final _controller = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final codigo = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (codigo.length != 6) {
      setState(() => _erro = 'O número do pedido tem 6 dígitos.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('reivindicarPerfilPrestador')
          .call({'codigo': codigo});
      final pedidos = (r.data is Map ? (r.data as Map)['pedidos'] : 0) as num? ?? 0;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(pedidos > 0
            ? 'Perfil ativado! Você tem $pedidos pedido(s) de cliente esperando.'
            : 'Perfil ativado! Os próximos pedidos chegam direto aqui no app.'),
      ));
    } on FirebaseFunctionsException catch (e) {
      setState(() => _erro = e.message ?? 'Não foi possível validar o número.');
    } catch (_) {
      setState(() => _erro = 'Não foi possível validar o número. Tente de novo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Número do pedido'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Digite o número do pedido (6 números) que veio no aviso do PrestadorAki no WhatsApp.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w700),
            decoration: InputDecoration(counterText: '', errorText: _erro, hintText: '000000'),
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _enviando ? null : _confirmar,
          child: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Ativar'),
        ),
      ],
    );
  }
}
