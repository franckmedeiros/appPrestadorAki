import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../core/validators.dart';
import '../../widgets/decorative_header.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/password_requirements_hint.dart';

/// Tela de trocar a senha estando logado — aberta por "Alterar senha" em
/// Meu perfil (ver UserProfileScreen).
///
/// Diferente de "Esqueci minha senha" (ForgotPasswordScreen), que manda um
/// link por e-mail pra quem NÃO consegue entrar. As duas precisam existir e
/// não substituem uma à outra: quem está dentro do app e só quer trocar a
/// senha não deveria ter que sair, pedir link e voltar pelo e-mail.
///
/// Pede a senha ATUAL de propósito — ver o comentário em
/// `AuthController.updatePassword` sobre por que reautenticar é o ponto
/// central desta tela, e não formalidade.
///
/// Volta `true` pelo `pop` quando a troca deu certo, pra quem abriu avisar
/// o usuário: mostrar a confirmação aqui não funcionaria, porque a tela
/// sai da frente no mesmo instante.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _atualController = TextEditingController();
  final _novaController = TextEditingController();
  final _confirmaController = TextEditingController();

  bool _esconderAtual = true;
  bool _esconderNova = true;
  bool _esconderConfirma = true;

  /// `AuthController.errorMessage` é compartilhado por todo o app e pode
  /// chegar aqui já preenchido por uma falha anterior (um login que deu
  /// errado, por exemplo). Sem esta trava, a tela abriria acusando um erro
  /// que não tem nada a ver com a troca de senha.
  bool _jaTentouSalvar = false;

  @override
  void dispose() {
    _atualController.dispose();
    _novaController.dispose();
    _confirmaController.dispose();
    super.dispose();
  }

  Future<void> _salvar(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _jaTentouSalvar = true);
    final ok = await auth.updatePassword(
      senhaAtual: _atualController.text,
      novaSenha: _novaController.text,
    );
    if (!mounted) return;
    // Erro nenhum aqui: `auth.errorMessage` já aparece no formulário (o
    // Consumer redesenha), e a tela fica aberta pra pessoa corrigir.
    if (ok) Navigator.of(context).pop(true);
  }

  Widget _olho(bool escondido, VoidCallback alternar) {
    return IconButton(
      icon: Icon(
        escondido ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: AppColors.muted,
        size: 20,
      ),
      onPressed: alternar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecorativeHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    // Navigator, e não `context.pop()` do go_router: esta
                    // tela é empilhada com MaterialPageRoute (ver
                    // UserProfileScreen), fora das rotas nomeadas.
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Alterar senha',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Confirme a senha atual e escolha uma nova',
                    style: TextStyle(fontSize: 13.5, color: Colors.white70),
                  ),
                ],
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LabeledTextField(
                        label: 'Senha atual',
                        controller: _atualController,
                        hintText: 'A senha que você usa hoje',
                        obscureText: _esconderAtual,
                        prefixIcon: Icons.lock_outline,
                        textInputAction: TextInputAction.next,
                        // Só "não deixe em branco": a senha atual foi
                        // criada sob a régua que valia na época dela, e
                        // exigir a política nova aqui barraria quem
                        // justamente quer trocar por uma senha melhor.
                        validator: validateLoginPassword,
                        suffixIcon: _olho(
                          _esconderAtual,
                          () => setState(() => _esconderAtual = !_esconderAtual),
                        ),
                      ),
                      const SizedBox(height: 18),
                      LabeledTextField(
                        label: 'Nova senha',
                        controller: _novaController,
                        hintText: 'Senha forte',
                        obscureText: _esconderNova,
                        prefixIcon: Icons.lock_reset_outlined,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final erro = validateStrongPassword(value);
                          if (erro != null) return erro;
                          if (value == _atualController.text) {
                            return 'A nova senha precisa ser diferente da atual';
                          }
                          return null;
                        },
                        suffixIcon: _olho(
                          _esconderNova,
                          () => setState(() => _esconderNova = !_esconderNova),
                        ),
                      ),
                      PasswordRequirementsHint(controller: _novaController),
                      const SizedBox(height: 18),
                      LabeledTextField(
                        label: 'Repita a nova senha',
                        controller: _confirmaController,
                        hintText: 'Digite de novo',
                        obscureText: _esconderConfirma,
                        prefixIcon: Icons.lock_outline,
                        textInputAction: TextInputAction.done,
                        // A confirmação existe porque o campo é mascarado:
                        // um erro de digitação aqui trancaria a pessoa fora
                        // da própria conta, e ela só descobriria no próximo
                        // login.
                        validator: (value) => (value ?? '') == _novaController.text
                            ? null
                            : 'As senhas não são iguais',
                        suffixIcon: _olho(
                          _esconderConfirma,
                          () => setState(() => _esconderConfirma = !_esconderConfirma),
                        ),
                      ),
                      if (_jaTentouSalvar && auth.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                auth.errorMessage!,
                                style: const TextStyle(color: AppColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 26),
                      GradientPillButton(
                        label: 'Salvar nova senha',
                        isLoading: auth.isBusy,
                        onPressed: auth.isBusy ? null : () => _salvar(auth),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'A senha nova vale para todos os aparelhos. Se você entrou '
                        'em outro celular, será preciso digitar a nova senha lá.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
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
