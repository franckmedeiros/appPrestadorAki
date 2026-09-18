import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import 'blocked_users_controller.dart';
import 'models/content_report.dart';
import 'moderation_repository.dart';

/// Menu de moderação que aparece em cada avaliação — "Denunciar" e
/// "Bloquear este usuário".
///
/// Exigência da Apple (Guideline 1.2): conteúdo escrito por usuário
/// precisa ter os dois, ao alcance de quem vê o conteúdo. Por isso o menu
/// mora no próprio cartão da avaliação, e não escondido numa tela de
/// configurações — quem se incomodou com um comentário está olhando pra
/// ele naquele instante.
///
/// Usado nos dois lados: o cliente vendo o perfil público de um prestador
/// (ProviderPublicProfileScreen) e o prestador vendo as avaliações que
/// recebeu (MyReviewsScreen) — este último é, na prática, o caso mais
/// provável de abuso de verdade.
class ReviewModerationMenu extends StatelessWidget {
  const ReviewModerationMenu({
    super.key,
    required this.listingId,
    required this.autorUid,
    this.autorNome,
    this.conteudo,
  });

  /// Prestador em cujo perfil a avaliação está.
  final String listingId;

  /// Quem escreveu a avaliação (é o id do documento — ver ProviderRating).
  final String autorUid;

  final String? autorNome;
  final String? conteudo;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Opções',
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
      padding: EdgeInsets.zero,
      onSelected: (valor) {
        if (valor == 'denunciar') {
          _abrirDenuncia(context);
        } else if (valor == 'bloquear') {
          _confirmarBloqueio(context);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'denunciar',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.flag_outlined, size: 20),
            title: Text('Denunciar avaliação'),
            visualDensity: VisualDensity.compact,
          ),
        ),
        PopupMenuItem(
          value: 'bloquear',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block, size: 20),
            title: Text('Bloquear este usuário'),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Future<void> _abrirDenuncia(BuildContext context) async {
    final motivo = await showModalBottomSheet<_ResultadoDaDenuncia>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FolhaDeDenuncia(),
    );
    if (motivo == null || !context.mounted) return;

    try {
      await context.read<ModerationRepository>().denunciarAvaliacao(
            listingId: listingId,
            autorUid: autorUid,
            motivo: motivo.motivo,
            detalhe: motivo.detalhe,
            conteudo: conteudo,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Denúncia enviada. Vamos analisar em até 24 horas.'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar a denúncia. $e')),
      );
    }
  }

  Future<void> _confirmarBloqueio(BuildContext context) async {
    final nome = (autorNome == null || autorNome!.trim().isEmpty) ? 'este usuário' : autorNome!.trim();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bloquear $nome?'),
        content: const Text(
          'Você deixa de ver as avaliações e os comentários dessa pessoa. '
          'Ela não é avisada do bloqueio, e você pode desfazer isso quando '
          'quiser em Meu perfil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
    if (confirmou != true || !context.mounted) return;

    try {
      await context.read<BlockedUsersController>().bloquear(autorUid, nome: autorNome);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nome foi bloqueado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível bloquear. $e')),
      );
    }
  }
}

class _ResultadoDaDenuncia {
  _ResultadoDaDenuncia(this.motivo, this.detalhe);

  final MotivoDaDenuncia motivo;
  final String? detalhe;
}

/// Escolha do motivo. Motivo obrigatório e detalhe opcional: sem o motivo,
/// quem for analisar recebe só "alguém não gostou disso", que não ajuda a
/// decidir nada em 24 horas.
class _FolhaDeDenuncia extends StatefulWidget {
  const _FolhaDeDenuncia();

  @override
  State<_FolhaDeDenuncia> createState() => _FolhaDeDenunciaState();
}

class _FolhaDeDenunciaState extends State<_FolhaDeDenuncia> {
  MotivoDaDenuncia? _motivo;
  final _detalhe = TextEditingController();

  @override
  void dispose() {
    _detalhe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Sobe junto com o teclado — sem isso o campo de detalhe fica
      // escondido atrás dele.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Denunciar avaliação',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Conte o que há de errado. Analisamos em até 24 horas.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              for (final m in MotivoDaDenuncia.values)
                RadioListTile<MotivoDaDenuncia>(
                  value: m,
                  groupValue: _motivo,
                  onChanged: (v) => setState(() => _motivo = v),
                  title: Text(m.label, style: const TextStyle(fontSize: 14)),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _detalhe,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Quer explicar melhor? (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _motivo == null
                    ? null
                    : () => Navigator.of(context).pop(
                          _ResultadoDaDenuncia(_motivo!, _detalhe.text),
                        ),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Enviar denúncia'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
