import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_theme.dart';
import '../core/provider_photos_service.dart';

/// Grade de fotos de trabalhos feitos, com adicionar e remover.
///
/// POR QUE ISSO IMPORTA (pedido do Franck): o perfil hoje se vende por
/// texto — categoria, cidade, uma bio. Para um pedreiro ou um jardineiro,
/// a prova do trabalho é a foto do trabalho. Sem ela, o cliente escolhe
/// entre dois nomes iguais.
///
/// SOBE NA HORA, não ao salvar o perfil. Uma foto escolhida já vira URL no
/// Storage antes de voltar pra tela. Assim o prestador vê o resultado
/// imediatamente, e uma edição abandonada no meio não perde as fotos que
/// ele já tinha conseguido enviar — o preço é que uma foto adicionada e
/// não salva fica no Storage sem ninguém apontando pra ela, o que custa
/// centavos e nunca aparece pra ninguém.
class ServicePhotosField extends StatefulWidget {
  const ServicePhotosField({
    super.key,
    required this.uid,
    required this.fotos,
    required this.onChanged,
  });

  final String uid;
  final List<String> fotos;
  final ValueChanged<List<String>> onChanged;

  @override
  State<ServicePhotosField> createState() => _ServicePhotosFieldState();
}

class _ServicePhotosFieldState extends State<ServicePhotosField> {
  bool _enviando = false;

  bool get _cheio => widget.fotos.length >= ProviderPhotosService.maximoDeFotos;

  Future<void> _adicionar() async {
    if (_cheio || _enviando) return;

    final fonte = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (fonte == null || !mounted) return;

    setState(() => _enviando = true);
    try {
      // Comprime ANTES de sair do celular. Uma foto de celular moderno tem
      // 4 a 8 MB; a 1600px com qualidade 80 ela fica em alguns décimos
      // disso, sem diferença visível num card. Isso é o que decide se o
      // prestador no 4G consegue subir a foto — e se o cliente consegue
      // abrir o perfil sem esperar.
      final escolhida = await ImagePicker().pickImage(
        source: fonte,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (escolhida == null) {
        if (mounted) setState(() => _enviando = false);
        return;
      }
      final url = await ProviderPhotosService.instance.enviar(
        uid: widget.uid,
        arquivo: File(escolhida.path),
      );
      if (!mounted) return;
      widget.onChanged([...widget.fotos, url]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar a foto.\n$e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _remover(String url) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover esta foto?'),
        content: const Text('Ela deixa de aparecer no seu perfil.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    // Tira da lista primeiro: é ela que o cliente vê. Apagar o arquivo é
    // faxina, e não pode segurar a tela (ver ProviderPhotosService.apagar).
    widget.onChanged(widget.fotos.where((f) => f != url).toList());
    await ProviderPhotosService.instance.apagar(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Fotos dos seus serviços',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
            const Spacer(),
            Text(
              '${widget.fotos.length}/${ProviderPhotosService.maximoDeFotos}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final url in widget.fotos)
              _Miniatura(url: url, onRemover: () => _remover(url)),
            if (!_cheio) _BotaoAdicionar(enviando: _enviando, onTap: _adicionar),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.fotos.isEmpty
              ? 'Mostre trabalhos que você já fez. É o que faz o cliente '
                  'escolher você e não outro nome parecido.'
              : 'Arraste para o lado no seu perfil público para ver como ficou.',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.url, required this.onRemover});

  final String url;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                // Sem isso, uma URL quebrada vira o retângulo cinza de erro
                // do Flutter e a pessoa não entende o que aconteceu.
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.background,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: AppColors.muted, size: 22),
                ),
                loadingBuilder: (context, child, progresso) => progresso == null
                    ? child
                    : Container(
                        color: AppColors.background,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemover,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotaoAdicionar extends StatelessWidget {
  const _BotaoAdicionar({required this.enviando, required this.onTap});

  final bool enviando;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enviando ? null : onTap,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.muted.withValues(alpha: 0.35),
            style: BorderStyle.solid,
          ),
        ),
        child: enviando
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: AppColors.muted, size: 22),
                  SizedBox(height: 4),
                  Text('Adicionar', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
      ),
    );
  }
}
