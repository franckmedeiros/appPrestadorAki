import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/auth_controller.dart';
import 'client_auth_gate.dart';
import 'models/provider_listing.dart';
import 'service_requests_repository.dart';

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
  DateTime? _preferredDate;

  bool _saving = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _preferredDate = picked);
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
      await context.read<ServiceRequestsRepository>().create(
            clientName: clientName,
            provider: widget.listing,
            description: _descriptionController.text.trim(),
            addressText: _addressController.text.trim(),
            preferredDate: _preferredDate == null
                ? null
                : '${_preferredDate!.year.toString().padLeft(4, '0')}-'
                    '${_preferredDate!.month.toString().padLeft(2, '0')}-'
                    '${_preferredDate!.day.toString().padLeft(2, '0')}',
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
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  _preferredDate == null
                      ? 'Quando você precisa? (opcional)'
                      : '${_preferredDate!.day.toString().padLeft(2, '0')}/'
                          '${_preferredDate!.month.toString().padLeft(2, '0')}/'
                          '${_preferredDate!.year}',
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
