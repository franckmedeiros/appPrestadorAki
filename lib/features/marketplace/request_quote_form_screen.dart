import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/auth_controller.dart';
import '../../core/date_text_utils.dart';
import '../../widgets/mask_text_input_formatter.dart';
import 'budget_requests_repository.dart';
import 'client_auth_gate.dart';
import 'models/provider_listing.dart';

/// Formulário de "solicitar orçamento" — o primeiro contato do cliente com
/// um prestador do diretório. Recebe o `ProviderListing` já carregado via
/// `extra` do go_router (ver router/app_router.dart), evitando ler o
/// Firestore de novo.
class RequestQuoteFormScreen extends StatefulWidget {
  const RequestQuoteFormScreen({super.key, required this.listing});

  final ProviderListing listing;

  @override
  State<RequestQuoteFormScreen> createState() => _RequestQuoteFormScreenState();
}

class _RequestQuoteFormScreenState extends State<RequestQuoteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  // Digitável, já vem preenchido com a data de hoje (decisão combinada
  // com o Franck) em vez de só um botão que abre o calendário vazio — a
  // pessoa edita se quiser outra data, ou apaga se realmente não tiver
  // preferência (ver core/date_text_utils.dart).
  late final _dateController = TextEditingController(text: formatDateDdMmYyyy(DateTime.now()));
  final _dateMask = MaskTextInputFormatter('##/##/####');

  bool _saving = false;
  String? _error;
  bool _sent = false;

  // Telefone da própria conta (`clients/{uid}.whatsapp`, gravado
  // obrigatoriamente no cadastro — ver AuthController.register) — vai
  // junto no pedido (`Budget.clientPhone`) pra permitir o prestador casar
  // esse cliente por telefone com um cadastro já existente (ver
  // CustomersRepository.findOrCreateForClient), em vez de só pelo nome.
  String? _ownPhone;

  @override
  void initState() {
    super.initState();
    _prefillAddress();
  }

  // Prévia do endereço a partir do perfil de quem está solicitando (Editar
  // perfil > endereço pessoal) — poupa digitar de novo o que já está
  // cadastrado. Continua editável: quem for atender num endereço diferente
  // (ex.: outra casa, endereço de um parente) só apaga e digita o certo.
  Future<void> _prefillAddress() async {
    try {
      final data = await context.read<AuthController>().fetchOwnProfileData();
      _ownPhone = data['whatsapp'] as String?;
      final address = _formatProfileAddress(data);
      if (address.isNotEmpty && mounted && _addressController.text.isEmpty) {
        setState(() => _addressController.text = address);
      }
    } catch (_) {
      // Sem endereço salvo ou falha ao buscar: o campo só fica vazio,
      // sem travar o formulário — a pessoa digita na mão normalmente.
    }
  }

  String _formatProfileAddress(Map<String, dynamic> data) {
    final parts = <String>[];
    final street = (data['addressStreet'] as String?)?.trim();
    if (street != null && street.isNotEmpty) parts.add(street);
    final neighborhood = (data['addressNeighborhood'] as String?)?.trim();
    if (neighborhood != null && neighborhood.isNotEmpty) parts.add(neighborhood);
    final city = (data['addressCity'] as String?)?.trim();
    final uf = (data['addressState'] as String?)?.trim();
    if (city != null && city.isNotEmpty) {
      parts.add((uf != null && uf.isNotEmpty) ? '$city - $uf' : city);
    } else if (uf != null && uf.isNotEmpty) {
      parts.add(uf);
    }
    return parts.join(', ');
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = tryParseDateDdMmYyyy(_dateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dateController.text = formatDateDdMmYyyy(picked));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Defensivo: normalmente já se chega aqui logado como cliente (a tela
    // de perfil público pede conta antes de empurrar pra este formulário),
    // mas não custa garantir de novo — evita depender só do caminho de
    // navegação pra uma ação que grava dado com o uid de quem envia.
    if (!await ensureClientAccount(context)) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final clientName = context.read<AuthController>().displayName;
      // `create` retorna `null` quando o prestador ainda não tem conta no
      // app (listagem "não reivindicada") — não tem onde gravar o pedido
      // nesse caso; a tela cai no mesmo fluxo de convite manual de sempre
      // (ver `widget.listing.claimed` no `build`, abaixo).
      await context.read<BudgetRequestsRepository>().create(
            clientName: clientName,
            provider: widget.listing,
            description: _descriptionController.text.trim(),
            addressText: _addressController.text.trim(),
            preferredDate: _dateController.text.trim().isEmpty
                ? null
                : _dateController.text.trim(),
            clientPhone: _ownPhone,
          );
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível enviar a solicitação.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Mensagem de convite pro prestador "não reivindicado" — o cliente é
  // quem escolhe compartilhar isso (por WhatsApp, SMS, etc.), o app nunca
  // guarda nem envia o contato do prestador sozinho. O link do app ainda é
  // um placeholder honesto: só existe de verdade quando o app for
  // publicado numa loja (ou tiver uma página pra apontar).
  String _inviteMessage() =>
      'Oi! Encontrei você no PrestadorAki e gostaria de solicitar um orçamento: '
      '${_descriptionController.text.trim()}. Baixe o app e crie uma conta '
      'gratuita pra responder: [link do app aqui]';

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Solicitação enviada')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              const Text('Sua solicitação foi enviada!',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 8),
              if (!widget.listing.claimed) ...[
                const Text(
                  'Esse profissional ainda não usa o PrestadorAki. Convide-o '
                  'pra que ele veja sua solicitação — copie a mensagem abaixo '
                  'e mande pra ele por WhatsApp ou onde preferir:',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_inviteMessage()),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _inviteMessage()));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Mensagem copiada!')));
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar mensagem de convite'),
                ),
              ] else
                const Text(
                    'O profissional foi notificado e pode responder pelo próprio PrestadorAki.'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Concluir'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Orçamento com ${widget.listing.name}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Descreva o que você precisa'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Descreva o serviço' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Endereço'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Informe o endereço' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dateController,
                keyboardType: TextInputType.datetime,
                inputFormatters: [_dateMask],
                decoration: InputDecoration(
                  labelText: 'Quando você precisa? (opcional)',
                  hintText: 'DD/MM/AAAA',
                  prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                  suffixIcon: IconButton(
                    tooltip: 'Escolher no calendário',
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    onPressed: _pickDate,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar solicitação'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
