import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../../widgets/state_city_fields.dart';
import 'customers_repository.dart';
import 'models/customer.dart';

/// Formulário de cliente — cria um novo (`customer == null`) ou edita um
/// já existente (`customer` preenchido, ver `CustomersListScreen`, que
/// agora abre isso ao tocar num card da lista). Visual em cards com ícone
/// (nome/telefone/UF/cidade) + cartão de dica, a partir de um mockup que
/// o Franck mandou.
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final Customer? customer;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.customer?.name ?? '');
  late final _phoneController =
      TextEditingController(text: widget.customer?.phone ?? widget.customer?.whatsapp ?? '');
  late String? _city = widget.customer?.addressCity;
  late String? _uf = widget.customer?.addressState;

  final _phoneMask = MaskTextInputFormatter('(##) #####-####');

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.customer != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = context.read<CustomersRepository>();
      if (_isEditing) {
        await repository.update(
          widget.customer!.id,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          addressCity: (_city ?? '').trim(),
          addressState: (_uf ?? '').trim().toUpperCase(),
        );
      } else {
        await repository.create(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          addressCity: (_city ?? '').trim(),
          addressState: (_uf ?? '').trim().toUpperCase(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o cliente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(_isEditing ? 'Editar cliente' : 'Novo cliente'),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.person_add_alt_1_outlined, color: Colors.white),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isEditing
                    ? 'Atualize os dados do cliente'
                    : 'Adicione os dados para cadastrar um novo cliente',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FieldCard(
                      icon: const Icon(Icons.person_outline, color: AppColors.primary, size: 19),
                      label: 'Nome completo',
                      required: true,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: 'Digite o nome completo do cliente',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Informe o nome'
                                : null,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _FieldCard(
                      icon: const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      label: 'Telefone / WhatsApp',
                      required: true,
                      helperText: 'Número usado para contato.',
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_phoneMask],
                        decoration: const InputDecoration(
                          hintText: '(00) 00000-0000',
                          prefixIcon: Icon(Icons.phone_outlined, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _FieldCard(
                            icon: const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.primary,
                              size: 14,
                            ),
                            label: 'UF',
                            required: true,
                            compact: true,
                            child: StateSelectorField(
                              key: ValueKey('customer-uf-$_uf'),
                              initialValue: _uf,
                              showLabel: false,
                              hint: 'Selecione',
                              onChanged: (uf) => setState(() {
                                _uf = uf;
                                _city = null;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _FieldCard(
                            icon: const Icon(
                              Icons.location_city_outlined,
                              color: AppColors.primary,
                              size: 14,
                            ),
                            label: 'Cidade',
                            required: true,
                            compact: true,
                            child: CitySelectorField(
                              key: ValueKey('customer-city-$_uf-$_city'),
                              uf: _uf,
                              initialValue: _city,
                              showLabel: false,
                              hint: 'Escolha',
                              onChanged: (city) =>
                                  setState(() => _city = city),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                    const _TipCard(
                      title: 'Dica',
                      message:
                          'Manter os dados atualizados facilita a comunicação e os próximos atendimentos.',
                    ),
                  ],
                ),
              ),
            ),

            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.muted.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          _isEditing
                              ? 'Salvar alterações'
                              : 'Salvar cliente',
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancelar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão de campo — ícone num círculo à esquerda, rótulo (com * quando
/// obrigatório) acima do campo de verdade, e um texto de ajuda opcional
/// embaixo. `compact` deixa o ícone menor pra caber lado a lado (ver UF/
/// Cidade), já que o cartão inteiro fica com metade da largura da tela.
class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.icon,
    required this.label,
    required this.child,
    this.required = false,
    this.helperText,
    this.compact = false,
  });

  final Widget icon;
  final String label;
  final Widget child;
  final bool required;
  final String? helperText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labelRow = Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 12,
              color: AppColors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(
          color: AppColors.muted.withValues(alpha: 0.10),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.07),
                        shape: BoxShape.circle,
                      ),
                      child: icon,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: labelRow),
                  ],
                ),
                const SizedBox(height: 7),
                child,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      labelRow,
                      const SizedBox(height: 7),
                      child,
                      if (helperText != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          helperText!,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}


/// Cartão de dica - fundo laranja bem clarinho, ícone de "i" circulado,
/// título e mensagem, com uma decoração ilustrativa simples em ícones à
/// direita (mesma ideia da decoração do cartão de saudação do Dashboard -
/// ver DashboardScreen._GreetingDecoration -, redesenhada aqui porque o
/// motivo visual é outro, mas o app não tem asset de ilustração de
/// verdade em nenhum dos dois casos).
class _TipCard extends StatelessWidget {
  const _TipCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 1.4),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.info_outline, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: AppColors.ink, fontSize: 11.5, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _TipDecoration(),
        ],
      ),
    );
  }
}

/// Decoração ilustrativa simples (ficha de cliente + selo de check) só
/// pra dar um toque visual ao cartão de dica, no lugar da ilustração de
/// verdade do mockup - não temos esse asset no app.
class _TipDecoration extends StatelessWidget {
  const _TipDecoration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 0,
            top: 2,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(6),
              child: const Icon(Icons.badge_outlined, size: 16, color: AppColors.primary),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
