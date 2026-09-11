import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/validators.dart';
import '../../widgets/decorative_header.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/mask_text_input_formatter.dart';
import '../../widgets/password_requirements_hint.dart';

/// Ponto único de "gate" pro lado do cliente do marketplace, depois da
/// mudança de ideia: buscar e ver o perfil público de um prestador NÃO
/// precisa de conta — só ações que realmente exigem saber quem é a pessoa
/// (favoritar, solicitar orçamento, ver favoritos/solicitações salvas)
/// pedem login/cadastro, e pedem na hora, sem tirar o cliente da tela onde
/// ele estava.
///
/// Conta unificada: quem já está autenticado (prestador ou não) já pode
/// usar ações de cliente direto — a versão antiga forçava logout de quem
/// estava "logado como prestador" (uma conta era OU prestador OU cliente);
/// isso não existe mais (ver AuthController). Só garante que existe um
/// `clients/{uid}` de base, criando na hora se for a primeira ação de
/// cliente dessa conta (ex.: um prestador favoritando outro profissional
/// pela primeira vez).
///
/// Uso: `if (!await ensureClientAccount(context)) return;` antes de
/// qualquer ação que precise de `clients/{uid}`.
Future<bool> ensureClientAccount(BuildContext context) async {
  final auth = context.read<AuthController>();

  if (auth.status == AuthStatus.authenticated) {
    await auth.ensureClientDocument();
    return true;
  }

  if (!context.mounted) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ClientAuthGateSheet(),
  );
  return result ?? false;
}

/// Convite pra criar/entrar numa conta — usado no lugar do conteúdo real
/// nas abas "Favoritos"/"Minhas solicitações" quando quem está olhando
/// ainda é um convidado (busca e perfil público continuam livres; só essas
/// ações que dependem de identidade pedem conta).
///
/// O botão manda pra aba "Perfil" (que mostra a tela de boas-vindas pra
/// quem não tem conta, ver UserProfileScreen/WelcomeScreen) em vez de
/// abrir a folha "Crie uma conta grátis" que aparecia por cima — pedido
/// do Franck: entrar/criar conta é sempre no mesmo lugar do app, uma
/// porta só, em vez de um formulário diferente em cada tela.
///
/// A folha (`ensureClientAccount`) continua existindo e sendo usada onde
/// ela faz sentido: no MEIO de uma ação (favoritar um prestador na busca,
/// enviar um pedido de orçamento), onde tirar a pessoa da tela faria ela
/// perder o que estava fazendo.
class ClientSignInPrompt extends StatelessWidget {
  const ClientSignInPrompt({
    super.key,
    required this.icon,
    required this.message,
    this.onPressed,
  });

  final IconData icon;
  final String message;

  /// Deixa null pra usar o comportamento padrão (ir pra aba "Perfil").
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onPressed ?? () => context.go('/perfil'),
              child: const Text('Entrar ou criar conta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientAuthGateSheet extends StatefulWidget {
  const _ClientAuthGateSheet();

  @override
  State<_ClientAuthGateSheet> createState() => _ClientAuthGateSheetState();
}

enum _Mode { login, register }

class _ClientAuthGateSheetState extends State<_ClientAuthGateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneMask = MaskTextInputFormatter('(##) #####-####');
  _Mode _mode = _Mode.register;
  bool _senhaEscondida = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    final ok = _mode == _Mode.login
        ? await auth.login(_emailController.text.trim(), _passwordController.text)
        : await auth.register(
            _nameController.text.trim(),
            _emailController.text.trim(),
            _passwordController.text,
            phone: _phoneController.text.trim(),
          );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    final criando = _mode == _Mode.register;

    // Mesma linguagem visual das telas de Login/Cadastro (cabeçalho em
    // gradiente + cartão branco + campos rotulados + botão em pílula) —
    // pedido do Franck: "se eu não estou logado e clico pra solicitar
    // orçamento, ele abre a tela antiga de login; ajustar pra tela nova".
    //
    // Continua sendo uma FOLHA que sobe por cima, e não a LoginScreen de
    // verdade, de propósito: quem chega aqui está no meio de uma ação
    // (enviar um pedido de orçamento, favoritar). Mandar a pessoa pra
    // outra tela faria ela perder o que estava preenchendo — a folha
    // resolve a conta e devolve a pessoa exatamente onde ela parou. O que
    // estava velho era a aparência, não o formato.
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `removeTop`: o DecorativeHeader tem um SafeArea dentro (ele
          // normalmente fica no TOPO de uma tela, colado na barra de
          // status). Numa folha que sobe de baixo isso viraria um vão
          // vazio de uns 40px dentro do cabeçalho, porque o SafeArea
          // continua enxergando o recorte da tela inteira.
          MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: DecorativeHeader(
              height: 120,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    criando ? 'Crie uma conta grátis' : 'Bem-vindo de volta!',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Só pro prestador saber com quem está falando.',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (criando) ...[
                      LabeledTextField(
                        label: 'Seu nome',
                        controller: _nameController,
                        hintText: 'Nome completo',
                        prefixIcon: Icons.person_outline,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
                      ),
                      const SizedBox(height: 16),
                      LabeledTextField(
                        label: 'Telefone',
                        controller: _phoneController,
                        hintText: '(00) 00000-0000',
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_phoneMask],
                        prefixIcon: Icons.phone_outlined,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                          return digits.length < 10 ? 'Informe um telefone válido' : null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    LabeledTextField(
                      label: 'E-mail',
                      controller: _emailController,
                      hintText: 'seuemail@exemplo.com',
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.mail_outline,
                      textInputAction: TextInputAction.next,
                      validator: (value) => validateEmail(value),
                    ),
                    const SizedBox(height: 16),
                    LabeledTextField(
                      label: criando ? 'Senha forte' : 'Senha',
                      controller: _passwordController,
                      hintText: '••••••••',
                      obscureText: _senhaEscondida,
                      prefixIcon: Icons.lock_outline,
                      textInputAction: TextInputAction.done,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _senhaEscondida
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.muted,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _senhaEscondida = !_senhaEscondida),
                      ),
                      validator: criando ? validateStrongPassword : validateLoginPassword,
                    ),
                    if (criando) PasswordRequirementsHint(controller: _passwordController),
                    if (auth.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(auth.errorMessage!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 24),
                    GradientPillButton(
                      label: criando ? 'Criar conta' : 'Entrar',
                      isLoading: auth.isBusy,
                      onPressed: auth.isBusy ? null : () => _submit(auth),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: auth.isBusy
                            ? null
                            : () => setState(
                                () => _mode = criando ? _Mode.login : _Mode.register),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                            children: [
                              TextSpan(text: criando ? 'Já tem conta? ' : 'Não tem conta? '),
                              TextSpan(
                                text: criando ? 'Entrar' : 'Cadastre-se',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
