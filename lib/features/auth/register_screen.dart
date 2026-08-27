import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../marketplace/models/service_category.dart';

/// Cadastro unificado (decisão combinada com o Franck): toda conta nasce
/// como cliente; "também quero oferecer serviços" é um opt-in ADICIONAL,
/// não uma escolha exclusiva — quem marca vira cliente E prestador ao
/// mesmo tempo (ver AuthController.register/isProvider).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();

  bool _alsoProvider = false;
  ServiceCategory _category = ServiceCategory.eletricista;

  // Mesma ideia da LoginScreen/DashboardScreen: oferece biometria já no
  // cadastro, em vez de só depois do primeiro login — assim quem já sabe
  // que quer usar biometria nem precisa passar pelo cartão de oferta do
  // Dashboard depois. Continua funcionando pra qualquer conta.
  bool? _biometricAvailable;
  bool _useBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await context.read<AuthController>().biometricAvailable;
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await auth.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
      asProvider: _alsoProvider,
      category: _alsoProvider ? _category.wireValue : null,
      city: _alsoProvider ? _cityController.text.trim() : null,
      state: _alsoProvider ? _stateController.text.trim().toUpperCase() : null,
    );
    if (ok && _useBiometrics) {
      await auth.setBiometricEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
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
                  decoration: const InputDecoration(labelText: 'Seu nome'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Informe seu nome' : null,
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _alsoProvider,
                  onChanged: (value) => setState(() => _alsoProvider = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Também quero oferecer serviços'),
                  subtitle: const Text(
                    'Sua conta continua a mesma pra buscar e favoritar prestadores — isso '
                    'só adiciona a área de prestador (orçamentos, agenda, clientes).',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (_alsoProvider) ...[
                  const SizedBox(height: 8),
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
                          validator: (value) => (_alsoProvider && (value == null || value.trim().isEmpty))
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
                    'Cidade e categoria são o que faz você aparecer nas buscas dos clientes '
                    'no PrestadorAki — depois de uma ativação (avisamos por fora).',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
                if (_biometricAvailable == true) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _useBiometrics,
                    onChanged: (value) => setState(() => _useBiometrics = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Usar biometria pra entrar mais rápido'),
                    subtitle: const Text(
                      'Digital ou reconhecimento facial, na próxima vez que abrir o app. '
                      'Dá pra ativar depois também, quando quiser.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
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
                      : const Text('Criar conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
