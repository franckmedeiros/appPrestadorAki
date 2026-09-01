import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/provider_logo_service.dart';
import '../../core/provider_bio_ai_service.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../../widgets/state_city_fields.dart';
import '../../widgets/service_category_field.dart';
import '../marketplace/models/provider_listing.dart';
import '../marketplace/models/service_category.dart';
import '../marketplace/provider_directory_repository.dart';

/// Formulário de edição dos dados do próprio usuário — igual ao pedido
/// do Franck ("no meu perfil, deveria ficar assim", com referência ao
/// app Resenha), depois ajustado por ele mesmo: sem data de nascimento
/// nem chave Pix — no lugar, e-mail (editável) e endereço. WhatsApp
/// continua pra todo mundo; categoria/cidade/UF de "área de atuação" só
/// pro prestador (são os mesmos campos preenchidos no cadastro, que
/// decidem em quais buscas ele aparece — ver
/// ProviderDirectoryRepository.upsertOwnListing). O endereço (CEP, rua e
/// número, bairro, cidade, UF) é um dado só da conta — nunca aparece no
/// perfil público do diretório.
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
  late final TextEditingController _emailController;
  final _whatsappController = TextEditingController();
  final _pixKeyController = TextEditingController();
  String _logoUrl = '';
  bool _uploadingLogo = false;
  final _bioController = TextEditingController();
  bool _geradorIABusy = false;
  final _cepController = TextEditingController();
  final _streetController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  String? _addressCity;
  String? _addressUf;
  String? _areaCity;
  String? _areaUf;
  final _streetFocusNode = FocusNode();
  ServiceCategory? _category;

  final _phoneMask = MaskTextInputFormatter('(##) #####-####');
  final _cepMask = MaskTextInputFormatter('#####-###');

  bool _loading = true;
  bool _isSaving = false;
  bool _lookingUpCep = false;
  String? _cepLookupError;
  String? _error;

  // Só existe pra prestador — reflete se a assinatura mensal (Google Play
  // Billing) está ativa agora (ver functions/src/subscription.ts):
  // 'active' com assinatura em dia, 'pending' quando ela não está ativa
  // (nunca chegou a assinar, cancelou, ou atrasou o pagamento além da
  // carência). Enquanto pendente, salvar aqui NÃO cria/atualiza a entrada
  // pública no diretório (ver _save abaixo) — a área de atuação fica salva
  // só em providers/{uid}, pronta pra quando a assinatura voltar a ativar
  // (a própria notificação da Play Store faz isso sozinha).
  String? _listingStatus;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _nameController = TextEditingController(text: auth.displayName);
    _emailController = TextEditingController(text: auth.currentUserEmail ?? '');
    final listing = widget.currentListing;
    _areaCity = listing?.city;
    _areaUf = listing?.state;
    if (listing != null) _category = listing.category;
    _loadOwnData();
  }

  Future<void> _loadOwnData() async {
    try {
      final data = await context.read<AuthController>().fetchOwnProfileData();
      if (!mounted) return;
      _cepController.text = data['addressZipCode'] as String? ?? '';
      _streetController.text = data['addressStreet'] as String? ?? '';
      _neighborhoodController.text = data['addressNeighborhood'] as String? ?? '';
      _addressCity = data['addressCity'] as String?;
      _addressUf = data['addressState'] as String?;
      _whatsappController.text = data['whatsapp'] as String? ?? '';
      _pixKeyController.text = data['pixKey'] as String? ?? '';
      _logoUrl = data['logoUrl'] as String? ?? '';
      _bioController.text = data['bio'] as String? ?? '';
      _listingStatus = data['listingStatus'] as String?;
      // A área de atuação vem de providers/{uid} (sempre existe, mesmo
      // 'pending' — ver functions/src/subscription.ts), não só do
      // `widget.currentListing` (que só reflete o diretório PÚBLICO, vazio
      // pra quem ainda não foi ativado). Só sobrescreve o que já veio do
      // `currentListing` no initState se providers/{uid} de fato tiver o
      // campo — evita apagar um valor bom com um branco à toa.
      final category = data['category'] as String?;
      final city = data['city'] as String?;
      final state = data['state'] as String?;
      if (category != null) _category = serviceCategoryFromWire(category);
      if (city != null && city.isNotEmpty) _areaCity = city;
      if (state != null && state.isNotEmpty) _areaUf = state;
    } catch (e) {
      // Sem isso, uma falha aqui (rede instável, Firestore fora do ar por
      // um instante etc. — visto acontecer no Android) deixava `_loading`
      // travado em `true` pra sempre, porque o `setState` que desliga o
      // spinner só rodava depois dessas linhas, nunca dentro de um
      // catch. A tela ficava girando o círculo de carregamento pra
      // sempre, sem erro nenhum aparecer. Agora ela sempre chega no
      // formulário — só os campos que dependiam de `providers/{uid}`
      // (endereço, WhatsApp, chave Pix, bio) podem aparecer em branco.
      if (!mounted) return;
      _error = 'Não foi possível carregar todos os seus dados agora. '
          'Alguns campos podem estar em branco — feche e abra essa tela de novo pra tentar carregar de novo.';
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Deixa escolher entre tirar uma foto na hora ou pegar da galeria —
  /// mesmo padrão do EnviarComprovanteButton do app Resenha.
  Future<ImageSource?> _escolherFonteDaLogo(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('Escolher da galeria'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                title: const Text('Tirar foto'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Toca no ícone do perfil pra trocar a logo — pedido do Franck pra
  /// substituir o campo antigo de "colar o link da imagem" por um upload
  /// de verdade (ver ProviderLogoService). Sobe pro Firebase Storage e já
  /// atualiza `_logoUrl` — o salvamento de fato (gravar a URL nova em
  /// providers/{uid}) só acontece quando o usuário confirmar em "Salvar",
  /// igual aos outros campos desse formulário.
  Future<void> _trocarLogo(BuildContext context) async {
    final fonte = await _escolherFonteDaLogo(context);
    if (fonte == null || !context.mounted) return;

    XFile? foto;
    try {
      foto = await ImagePicker().pickImage(
        source: fonte,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Não foi possível abrir ${fonte == ImageSource.camera ? 'a câmera' : 'a galeria'}.\n$e'),
        ),
      );
      return;
    }
    if (foto == null || !context.mounted) return;

    final uid = context.read<AuthController>().providerId;
    setState(() => _uploadingLogo = true);
    try {
      final url = await ProviderLogoService.instance.enviar(uid: uid, arquivo: File(foto.path));
      if (!mounted) return;
      setState(() {
        _logoUrl = url;
        _uploadingLogo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingLogo = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar a imagem.\n$e')),
      );
    }
  }

  /// Botões "Gerar com IA"/"Melhorar com IA" da seção Descrição — chama
  /// a Cloud Function gerarDescricaoPrestador (Gemini). [comRascunho]
  /// decide se manda o texto já escrito no campo (pra IA melhorar) ou
  /// nada (pra IA gerar do zero, só com categoria/cidade).
  Future<void> _gerarDescricao({required bool comRascunho}) async {
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha sua categoria de serviço primeiro.')),
      );
      return;
    }
    setState(() => _geradorIABusy = true);
    try {
      final descricao = await ProviderBioAiService.instance.gerar(
        categoria: _category!.label,
        cidade: _areaCity,
        estado: _areaUf,
        rascunho: comRascunho ? _bioController.text : null,
      );
      if (!mounted) return;
      setState(() {
        _bioController.text = descricao;
        _geradorIABusy = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _geradorIABusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Não foi possível gerar o texto agora.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _geradorIABusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível gerar o texto agora. Tente de novo.')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    _pixKeyController.dispose();
    _bioController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _neighborhoodController.dispose();

    _streetFocusNode.dispose();
    super.dispose();
  }

  bool get _isProvider => context.read<AuthController>().isProvider;

  /// Busca o endereço automaticamente a partir do CEP digitado — via
  /// ViaCEP (não existe uma API pública e gratuita dos Correios pra
  /// isso; o ViaCEP é o serviço padrão usado por apps brasileiros pra
  /// esse tipo de busca, consultando a mesma base dos Correios). Só
  /// dispara quando o CEP fica completo (8 dígitos, ver o `onChanged` do
  /// campo); falha em silêncio numa mensagem pequena embaixo do campo —
  /// o usuário sempre pode preencher rua/bairro/cidade na mão.
  Future<void> _lookupCep(String cep) async {
    setState(() {
      _lookingUpCep = true;
      _cepLookupError = null;
    });
    try {
      final response = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _cepLookupError = 'Não foi possível buscar o CEP agora.');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['erro'] == true) {
        setState(() => _cepLookupError = 'CEP não encontrado.');
        return;
      }
      final logradouro = data['logradouro'] as String?;
      setState(() {
        // Deixa a vírgula e o foco prontos pro usuário só completar com o
        // número da casa — o ViaCEP não devolve número nenhum.
        _streetController.text =
            (logradouro != null && logradouro.isNotEmpty) ? '$logradouro, ' : _streetController.text;
        _neighborhoodController.text = (data['bairro'] as String?) ?? _neighborhoodController.text;
        _addressCity = (data['localidade'] as String?) ?? _addressCity;
        _addressUf = (data['uf'] as String?) ?? _addressUf;
      });
      _streetController.selection =
          TextSelection.fromPosition(TextPosition(offset: _streetController.text.length));
      _streetFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cepLookupError = 'Não foi possível buscar o CEP agora.');
    } finally {
      if (mounted) setState(() => _lookingUpCep = false);
    }
  }

  /// Pede a senha atual antes de trocar o e-mail — o Firebase exige uma
  /// reautenticação recente pra esse tipo de operação sensível (senão
  /// lança `requires-recent-login`). Devolve `null` se o usuário cancelar.
  Future<String?> _promptCurrentPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirme sua senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pra trocar seu e-mail de login, digite sua senha atual.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Senha atual'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthController>();
    final newEmail = _emailController.text.trim();
    final emailChanged = newEmail != (auth.currentUserEmail ?? '');

    String? currentPassword;
    if (emailChanged) {
      currentPassword = await _promptCurrentPassword();
      if (!mounted) return;
      if (currentPassword == null || currentPassword.isEmpty) return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    if (emailChanged) {
      final emailOk = await auth.updateEmailAddress(newEmail, currentPassword!);
      if (!mounted) return;
      if (!emailOk) {
        setState(() {
          _isSaving = false;
          _error = auth.errorMessage ?? 'Não foi possível atualizar o e-mail.';
        });
        return;
      }
    }

    final name = _nameController.text.trim();
    final ok = await auth.updateOwnProfile(
      name: name,
      whatsapp: _whatsappController.text.trim(),
      addressZipCode: _cepController.text.trim(),
      addressStreet: _streetController.text.trim(),
      addressNeighborhood: _neighborhoodController.text.trim(),
      addressCity: (_addressCity ?? '').trim(),
      addressState: (_addressUf ?? '').trim().toUpperCase(),
      pixKey: _isProvider ? _pixKeyController.text.trim() : null,
      logoUrl: _isProvider ? _logoUrl.trim() : null,
      bio: _isProvider ? _bioController.text.trim() : null,
    );

    if (ok && _isProvider) {
      try {
        // Guarda a área de atuação em providers/{uid} independente do
        // status de ativação — não se perde enquanto listingStatus segue
        // 'pending'.
        final businessInfoOk = await auth.updateProviderBusinessInfo(
          category: _category!.wireValue,
          city: (_areaCity ?? '').trim(),
          state: (_areaUf ?? '').trim().toUpperCase(),
        );
        if (!businessInfoOk) {
          if (!mounted) return;
          setState(() {
            _isSaving = false;
            _error = auth.errorMessage ?? 'Dados salvos, mas não foi possível atualizar categoria/cidade.';
          });
          return;
        }
        // Só publica/atualiza a entrada pública do diretório (o que faz o
        // prestador aparecer na busca do cliente) se a assinatura estiver
        // ativa agora — ver functions/src/subscription.ts. Prestadores
        // antigos (sem esse campo ainda) continuam publicando normalmente.
        if (_listingStatus != 'pending') {
          await context.read<ProviderDirectoryRepository>().upsertOwnListing(
                name: name,
                category: _category!,
                city: (_areaCity ?? '').trim(),
                state: (_areaUf ?? '').trim().toUpperCase(),
                bio: _bioController.text.trim(),
                whatsapp: _whatsappController.text.trim(),
              );
        }
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
      // O `pop(emailChanged)` avisa a UserProfileScreen pra mostrar o
      // aviso sobre o link de confirmação — SnackBar não sobrevive bem
      // se disparado bem em cima de um pop desta própria tela.
      Navigator.of(context).pop(emailChanged);
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
                _ProfileHeader(
                  logoUrl: _logoUrl,
                  uploading: _uploadingLogo,
                  onTrocarFoto: () => _trocarLogo(context),
                  nameListenable: _nameController,
                  categoryLabel: isProvider ? _category?.label : null,
                ),
                const SizedBox(height: 24),
                const _SectionHeader(icon: Icons.person_outline, title: 'Informações pessoais'),
                const SizedBox(height: 12),
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
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) =>
                      (value == null || !value.contains('@')) ? 'Informe um e-mail válido' : null,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Se você trocar o e-mail, vamos pedir sua senha atual e mandar um '
                  'link de confirmação pro e-mail novo.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
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
                  const SizedBox(height: 20),
                  const _SectionHeader(icon: Icons.work_outline, title: 'Área de atuação'),
                  if (_listingStatus == 'pending') ...[
                    const SizedBox(height: 8),
                    const Card(
                      color: Color(0xFFFFF4E5),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '⏳ Sua assinatura mensal não está ativa no momento — assim que ela '
                          'for confirmada, você volta a aparecer nas buscas dos clientes.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ServiceCategorySelectorField(
                    label: 'Sua principal categoria de serviço',
                    initialValue: _category,
                    validator: (value) => value == null ? 'Selecione' : null,
                    onChanged: (value) => setState(() => _category = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: StateSelectorField(
                          key: ValueKey('area-uf-$_areaUf'),
                          initialValue: _areaUf,
                          validator: (value) =>
                              (value == null || value.isEmpty) ? 'Selecione' : null,
                          onChanged: (uf) => setState(() {
                            _areaUf = uf;
                            _areaCity = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: CitySelectorField(
                          key: ValueKey('area-city-$_areaUf-$_areaCity'),
                          uf: _areaUf,
                          initialValue: _areaCity,
                          validator: (value) =>
                              (value == null || value.isEmpty) ? 'Informe a cidade' : null,
                          onChanged: (city) => setState(() => _areaCity = city),
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
                  const SizedBox(height: 20),
                  const _SectionHeader(icon: Icons.credit_card_outlined, title: 'Dados de pagamento'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _pixKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Chave Pix (opcional)',
                      prefixIcon: Icon(Icons.qr_code_outlined),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Usada mais pra frente pra gerar o QR code no orçamento enviado ao cliente.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(icon: Icons.notes_outlined, title: 'Descrição'),
                  const SizedBox(height: 4),
                  const Text(
                    'Uma "carta de apresentação" curta pro cliente ver no seu perfil público.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _bioController,
                    maxLines: 4,
                    maxLength: 400,
                    enabled: !_geradorIABusy,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Ex.: Atendo residências e comércios, com atenção a prazos e '
                          'organização no serviço.',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _geradorIABusy ? null : () => _gerarDescricao(comRascunho: false),
                          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                          label: const Text('Gerar com IA'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_geradorIABusy || _bioController.text.trim().isEmpty)
                              ? null
                              : () => _gerarDescricao(comRascunho: true),
                          icon: _geradorIABusy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_fix_high_outlined, size: 18),
                          label: const Text('Melhorar com IA'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionHeader(icon: Icons.location_on_outlined, title: 'Endereço'),
                const SizedBox(height: 4),
                const Text(
                  'Fica só na sua conta — não aparece no seu perfil público.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cepController,
                  decoration: InputDecoration(
                    labelText: 'CEP (opcional)',
                    hintText: '00000-000',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    suffixIcon: _lookingUpCep
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_cepMask],
                  onChanged: (value) {
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length == 8) {
                      _lookupCep(digits);
                    } else if (_cepLookupError != null) {
                      setState(() => _cepLookupError = null);
                    }
                  },
                ),
                if (_cepLookupError != null) ...[
                  const SizedBox(height: 4),
                  Text(_cepLookupError!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _streetController,
                  focusNode: _streetFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Rua e número (opcional)',
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _neighborhoodController,
                  decoration: const InputDecoration(
                    labelText: 'Bairro (opcional)',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: StateSelectorField(
                        key: ValueKey('address-uf-$_addressUf'),
                        initialValue: _addressUf,
                        label: 'UF',
                        onChanged: (uf) => setState(() {
                          _addressUf = uf;
                          _addressCity = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: CitySelectorField(
                        key: ValueKey('address-city-$_addressUf-$_addressCity'),
                        uf: _addressUf,
                        initialValue: _addressCity,
                        label: 'Cidade (opcional)',
                        onChanged: (city) => setState(() => _addressCity = city),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Salvar alterações'),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: _SecurityFootnote(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho de seção (selo redondo com ícone + título em negrito) usado
/// em cada bloco do formulário - visual a partir de um mockup que o
/// Franck mandou. Só troca a aparência dos títulos que já existiam
/// (eram um Text simples); nenhuma validação/lógica do formulário muda.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.1),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }
}

/// Cabeçalho do formulário — avatar (mesma foto/upload de antes, só que
/// em destaque no topo em vez de escondido dentro de "Logo e
/// descrição"), nome (acompanha o campo "Nome completo" ao vivo, via
/// AnimatedBuilder) e categoria, com um botão "Alterar foto" explícito —
/// visual a partir de um mockup que o Franck mandou. `onTrocarFoto`
/// reaproveita o mesmo `_trocarLogo` de sempre; nada na lógica de upload
/// muda, só ganhou um segundo lugar (mais visível) pra disparar a mesma
/// ação — por isso o círculo antigo dentro de "Logo e descrição" saiu
/// dali, pra não ter dois jeitos de editar a mesma foto na mesma tela.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.logoUrl,
    required this.uploading,
    required this.onTrocarFoto,
    required this.nameListenable,
    required this.categoryLabel,
  });

  final String logoUrl;
  final bool uploading;
  final VoidCallback onTrocarFoto;
  final TextEditingController nameListenable;
  final String? categoryLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: uploading ? null : onTrocarFoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 76,
                height: 76,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.1),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: uploading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (logoUrl.trim().isEmpty
                        ? const Icon(Icons.storefront_outlined, color: AppColors.primary, size: 32)
                        : Image.network(
                            logoUrl.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image_outlined, color: AppColors.muted),
                          )),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    border: Border.fromBorderSide(BorderSide(color: AppColors.surface, width: 2)),
                  ),
                  child: const Icon(Icons.camera_alt_outlined, size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: nameListenable,
                builder: (context, _) => Text(
                  nameListenable.text.trim().isEmpty ? 'Seu nome' : nameListenable.text,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (categoryLabel != null && categoryLabel!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(categoryLabel!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: uploading ? null : onTrocarFoto,
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('Alterar foto'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Legenda de rodapé abaixo do botão salvar — puramente informativa, sem
/// nenhum link/ação (o mockup mostrava só o texto com um cadeado).
class _SecurityFootnote extends StatelessWidget {
  const _SecurityFootnote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 13, color: AppColors.muted),
        SizedBox(width: 6),
        Text(
          'Suas informações estão seguras conosco.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}
