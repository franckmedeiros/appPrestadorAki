/// Validação de e-mail reaproveitada nos formulários de cadastro/login/
/// edição de perfil — antes cada tela checava só `value.contains('@')`,
/// que aceita qualquer besteira como "a@a" (pedido do Franck: "fazer a
/// validação do email no cadastro, hj posso colocar email [qualquer]").
/// Não confirma que o endereço existe de verdade (só um e-mail de
/// confirmação enviado faria isso) — só barra formato claramente
/// inválido antes de gastar uma tentativa de cadastro no Firebase Auth.
final _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-zA-Z]{2,}$');

bool isValidEmail(String value) => _emailRegex.hasMatch(value.trim());

/// Mesma assinatura que os `validator:` de `TextFormField`/
/// `LabeledTextField` já usavam inline — só centraliza a regra.
String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Informe um e-mail válido';
  return isValidEmail(value) ? null : 'Informe um e-mail válido';
}
