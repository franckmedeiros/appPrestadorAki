import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/service_category.dart';
import '../marketplace/provider_directory_repository.dart';

/// Formulário de edição dos dados do próprio usuário — o "próximo passo
/// natural" que já estava documentado no DATA_MODEL.md e que o Franck
/// pediu direto ("hoje eu não consigo mudar os dados do usuário"), igual
/// ao app Resenha (EditPerfilScreen).
///
/// Pro cliente, só o nome é editável (é tudo que `clients/{uid}` guarda).
/// Pro prestador, também dá pra mudar categoria/cidade/UF — os mesmos
/// campos preenchidos no cadastro, que são o que decide em quais buscas
/// ele aparece (ver ProviderDirectoryRepository.upsertOwnListing).
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
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  ServiceCategory _category = ServiceCategory.eletricista;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _nameController = TextEditingController(text: auth.displayName);
    final listing = widget.currentListing;
    _cityController = TextEditingController(text: listing?.city ?? '');
    _stateController = TextEditingController(text: listing?.state ?? '');
    if (listing != null) _category = listing.category;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  bool get _isProvider => context.read<AuthController>().role == AccountRole.provider;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final auth = context.read<AuthController>();
    final name = _nameController.text.trim();
    final ok = await auth.updateOwnName(name);

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
          _error = 'Nome salvo, mas não foi possível atualizar categoria/cidade. Tente de novo.';
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
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
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
