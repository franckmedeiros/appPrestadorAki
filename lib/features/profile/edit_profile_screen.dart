import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/service_category.dart';
import '../marketplace/provider_directory_repository.dart';

/// Formulário de edição dos dados do próprio usuário — igual ao pedido
/// do Franck ("no meu perfil, deveria ficar assim", com referência ao
/// app Resenha): nome, data de nascimento (opcional), chave Pix e
/// WhatsApp pra todo mundo; categoria/cidade/UF só pro prestador (são os
/// mesmos campos preenchidos no cadastro, que decidem em quais buscas
/// ele aparece — ver ProviderDirectoryRepository.upsertOwnListing).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.currentListing});

  /// Perfil público atual do prestador, se já existir — `null` pro
  /// cliente, ou pro prestador que ainda não tem entrada no diretório por
  /// algum motivo (não deveria acontecer, mas os campos abaixo cobrem
  /// esse caso partindo em branco).
  final ProviderListing? currentListing;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _birthDateController = TextEditingController();
  final _pixKeyController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  ServiceCategory _category = ServiceCategory.eletricista;

  final _phoneMask = _MaskTextInputFormatter('(##) #####-####');
  final _dateMask = _MaskTextInputFormatter('##/##/####');

  DateTime? _birthDate;
  bool _loading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: context.read<AuthController>().displayName);
    final listing = widget.currentListing;
    _cityController.text = listing?.city ?? '';
    _stateController.text = listing?.state ?? '';
    if (listing != null) _category = listing.category;
    _loadOwnData();
  }

  Future<void> _loadOwnData() async {
    final data = await context.read<AuthController>().fetchOwnProfileData();
    if (!mounted) return;
    final birthTimestamp = data['birthDate'] as Timestamp?;
    if (birthTimestamp != null) {
      final date = birthTimestamp.toDate();
      _birthDate = date;
      _birthDateController.text = DateFormat('dd/MM/yyyy').format(date);
    }
    _pixKeyController.text = data['pixKey'] as String? ?? '';
    _whatsappController.text = data['whatsapp'] as String? ?? '';
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthDateController.dispose();
    _pixKeyController.dispose();
    _whatsappController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  bool get _isProvider => context.read<AuthController>().role == AccountRole.provider;

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Data de nascimento',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  /// Converte o texto digitado (com a máscara dd/mm/aaaa) numa data de
  /// verdade — devolve null se ainda estiver incompleto ou se a data não
  /// existir (ex: 31/02), pra não deixar passar algo tipo "31/02/2000"
  /// que o DateTime só "arredondaria" pra 03/03. Mesma lógica do app
  /// Resenha (EditPerfilScreen).
  DateTime? _parseTypedDate(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) return null;
    final day = int.tryParse(digits.substring(0, 2));
    final month = int.tryParse(digits.substring(2, 4));
    final year = int.tryParse(digits.substring(4, 8));
    if (day == null || month == null || year == null) return null;
    final date = DateTime(year, month, day);
    if (date.day != day || date.month != month || date.year != year) return null;
    return date;
  }

  void _onBirthDateTextChanged(String text) {
    final date = _parseTypedDate(text);
    _birthDate = (date != null && !date.isAfter(DateTime.now())) ? date : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final auth = context.read<AuthController>();
    final name = _nameController.text.trim();
    final ok = await auth.updateOwnProfile(
      name: name,
      birthDate: _birthDate,
      pixKey: _pixKeyController.text.trim(),
      whatsapp: _whatsappController.text.trim(),
    );

    if (ok && _isProvider) {
      try {
        await context.read<ProviderDirectoryRepository>().upsertOwnListing(
              name: name,
              category: _category,
              city: _cityController.text.trim(),
              state: _stateController.text.trim().toUpperCase(),
            );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _error = 'Dados salvos, mas não foi possível atualizar categoria/cidade. Tente de novo.';
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = auth.errorMessage ?? 'Não foi possível salvar as alterações.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isProvider = _isProvider;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: isProvider ? 'Nome ou razão social' : 'Seu nome',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _birthDateController,
                  decoration: InputDecoration(
                    labelText: 'Data de nascimento (opcional)',
                    hintText: 'dd/mm/aaaa',
                    prefixIcon: const Icon(Icons.cake_outlined),
                    suffixIcon: IconButton(
                      onPressed: _pickBirthDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_dateMask],
                  onChanged: _onBirthDateTextChanged,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length < 8) return 'Data incompleta';
                    final date = _parseTypedDate(value);
                    if (date == null) return 'Data inválida';
                    if (date.isAfter(DateTime.now())) return 'Data não pode ser no futuro';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pixKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Chave Pix (opcional)',
                    hintText: 'CPF, e-mail, telefone ou chave aleatória',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _whatsappController,
                  decoration: const InputDecoration(
                    labelText: 'Telefone/WhatsApp (opcional)',
                    hintText: '(00) 00000-0000',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_phoneMask],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    return digits.length < 10 ? 'Telefone incompleto' : null;
                  },
                ),
                if (isProvider) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ServiceCategory>(
                    initialValue: _category,
                    decoration:
                        const InputDecoration(labelText: 'Sua principal categoria de serviço'),
                    items: ServiceCategory.values
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                        .toList(),
                    onChanged: (value) => setState(() => _category = value ?? _category),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _cityController,
                          decoration: const InputDecoration(labelText: 'Cidade'),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? 'Informe a cidade'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          maxLength: 2,
                          decoration: const InputDecoration(labelText: 'UF', counterText: ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cidade e categoria são o que faz você aparecer nas buscas '
                    'dos clientes no PrestadorAki.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Salvar alterações'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Máscara de texto minimalista (sem depender de nenhum pacote externo —
/// menos uma dependência do Gradle pra dar problema, ver o histórico de
/// build do compileSdk). `#` no padrão vira "próximo dígito digitado";
/// qualquer outro caractere do padrão (espaço, parênteses, traço, barra)
/// é inserido literalmente. Usada tanto pro telefone quanto pra data.
class _MaskTextInputFormatter extends TextInputFormatter {
  _MaskTextInputFormatter(this.mask);

  final String mask;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    var digitIndex = 0;
    for (var i = 0; i < mask.length && digitIndex < digits.length; i++) {
      if (mask[i] == '#') {
        buffer.write(digits[digitIndex]);
        digitIndex++;
      } else {
        buffer.write(mask[i]);
      }
    }
    final text = buffer.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
