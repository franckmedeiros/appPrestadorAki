import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../widgets/decorative_header.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/mask_text_input_formatter.dart';

/// Aba "Meu perfil" pra quem ainda não tem sessão - login/cadastro
/// embutidos direto na tela (sem precisar abrir uma folha/modal), a
/// partir de um mockup que o Franck mandou. Mesmo cabeçalho ondulado
/// (DecorativeHeader) já usado em LoginScreen/RegisterScreen, com um
/// painel branco por cima contendo os dois modos (login/cadastro) que
/// alternam num só toque - parecido com o que ClientAuthGateSheet já
/// fazia como modal, só que sempre visível aqui, sem precisar tocar em
/// nada pra abrir.
///
/// Nota honesta: o mockup também tinha um texto "ou continue com" - não
/// incluído aqui porque o app não tem nenhum login social (Google/Apple)
/// de verdade, só e-mail/senha; um texto assim sem nada embaixo ficaria
/// enganoso.
class GuestProfilePanel extends StatefulWidget {
  const GuestProfilePanel({super.key, required this.onAuthenticated});

  /// Chamado depois de um login/cadastro bem-sucedido, pra tela pai
  /// recarregar os dados próprios (ver _UserProfileScreenState._signIn -
  /// o mesmo cuidado que já existia no fluxo antigo via ClientAuthGate).
  final VoidCallback onAuthenticated;

  @override
  State<GuestProfilePanel> createState() => _GuestProfilePanelState();
}

enum _Mode { register, login }

class _GuestProfilePanelState extends State<GuestProfilePanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneMask = MaskTextInputFormatter('(##) #####-####');
  // Pedido do Franck: quem toca em "Meu perfil" sem sessão via de cara
  // "Crie uma conta grátis" -- deveria abrir já em "Entrar na sua
  // conta" (a maioria de quem chega aqui sem sessão já tem conta, só
  // saiu ou trocou de aparelho; cadastro continua a um toque de
  // distância, só não é mais o padrão).
  _Mode _mode = _Mode.login;
  bool _obscurePassword = true;

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
    if (ok) widget.onAuthenticated();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isRegister = _mode == _Mode.register;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DecorativeHeader(
              height: 150,
              child: Text(
                'Meu perfil',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                        child: const Icon(Icons.person_outline, color: AppColors.primary, size: 28),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isRegister ? 'Crie uma conta grátis' : 'Entrar na sua conta',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isRegister
                            ? 'Vamos precisar de algumas informações pra começar.'
                            : 'Só pra gente saber quem é você e proteger sua conta.',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                      ),
                      const SizedBox(height: 22),
                      if (isRegister) ...[
                        _PanelField(
                          controller: _nameController,
                          hintText: 'Seu nome',
                          icon: Icons.person_outline,
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
                        ),
                        const SizedBox(height: 14),
                        _PanelField(
                          controller: _phoneController,
                          hintText: 'Telefone',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [_phoneMask],
                          validator: (value) {
                            final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                            return digits.length < 10 ? 'Informe um telefone válido' : null;
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      _PanelField(
                        controller: _emailController,
                        hintText: 'E-mail',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) =>
                            (value == null || !value.contains('@')) ? 'Informe um e-mail válido' : null,
                      ),
                      const SizedBox(height: 14),
                      _PanelField(
                        controller: _passwordController,
                        hintText: 'Senha (mínimo 8 caracteres)',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.muted,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (value) =>
                            (value == null || value.length < 8) ? 'Mínimo de 8 caracteres' : null,
                      ),
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(auth.errorMessage!, style: const TextStyle(color: AppColors.danger)),
                      ],
                      const SizedBox(height: 24),
                      GradientPillButton(
                        label: isRegister ? 'Criar conta' : 'Entrar',
                        icon: Icons.arrow_forward,
                        isLoading: auth.isBusy,
                        onPressed: auth.isBusy ? null : () => _submit(auth),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: TextButton(
                          onPressed: auth.isBusy
                              ? null
                              : () => setState(() => _mode = isRegister ? _Mode.login : _Mode.register),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(isRegister ? 'Já tem conta?' : 'Ainda não tenho conta'),
                              const Icon(Icons.chevron_right, size: 18),
                            ],
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
      ),
    );
  }
}

/// Campo do painel - ícone + hint dentro da caixa, sem rótulo separado
/// acima (diferente do LabeledTextField usado em Login/Cadastro/Editar
/// perfil) - assim mesmo no mockup que o Franck mandou pra esta tela.
class _PanelField extends StatelessWidget {
  const _PanelField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}
