import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';

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
/// ações que dependem de identidade pedem conta, e pedem na hora).
class ClientSignInPrompt extends StatelessWidget {
  const ClientSignInPrompt({super.key, required this.icon, required this.message, required this.onPressed});

  final IconData icon;
  final String message;
  final VoidCallback onPressed;

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
            ElevatedButton(onPressed: onPressed, child: const Text('Entrar ou criar conta')),
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
  final _passwordController = TextEditingController();
  _Mode _mode = _Mode.register;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
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
          );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _mode == _Mode.register ? 'Crie uma conta grátis' : 'Entrar na sua conta',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Só pra gente saber quem é você quando o prestador responder.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_mode == _Mode.register) ...[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Seu nome'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (value) =>
                    (value == null || !value.contains('@')) ? 'Informe um e-mail válido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha (mínimo 8 caracteres)'),
                validator: (value) =>
                    (value == null || value.length < 8) ? 'Mínimo de 8 caracteres' : null,
              ),
              if (auth.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(auth.errorMessage!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: auth.isBusy ? null : () => _submit(auth),
                child: auth.isBusy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_mode == _Mode.register ? 'Criar conta' : 'Entrar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: auth.isBusy
                    ? null
                    : () => setState(
                        () => _mode = _mode == _Mode.register ? _Mode.login : _Mode.register),
                child: Text(
                  _mode == _Mode.register ? 'Já tenho conta' : 'Ainda não tenho conta',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
