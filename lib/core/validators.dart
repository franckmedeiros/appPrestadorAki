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

/// Política de senha forte (pedido do Franck: "como o app vai pra nivel
/// nacional, deve ser ter seguranca grande") — usada só no CADASTRO de
/// senha nova (register/virar prestador/painel de convidado). De
/// propósito NÃO se aplica ao campo de senha do LOGIN (ver
/// `validateLoginPassword` abaixo): mudar a régua pra trás bloquearia,
/// na hora de entrar, qualquer conta já cadastrada com senha mais fraca
/// de antes dessa mudança — a senha continua válida no Firebase Auth, só
/// não pode ser CRIADA de novo assim.
const passwordMinLength = 10;

bool passwordHasUppercase(String value) => value.contains(RegExp(r'[A-Z]'));
bool passwordHasLowercase(String value) => value.contains(RegExp(r'[a-z]'));
bool passwordHasDigit(String value) => value.contains(RegExp(r'[0-9]'));
bool passwordHasSpecialChar(String value) =>
    value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]/\\;`~]'));

bool isStrongPassword(String value) =>
    value.length >= passwordMinLength &&
    passwordHasUppercase(value) &&
    passwordHasLowercase(value) &&
    passwordHasDigit(value) &&
    passwordHasSpecialChar(value);

/// Validator pro campo de senha em telas de CADASTRO (ver nota acima).
/// Mensagem aponta o primeiro requisito que falta, em vez de um "senha
/// fraca" genérico -- mais fácil de corrigir sem ficar tentando às cegas.
String? validateStrongPassword(String? value) {
  final v = value ?? '';
  if (v.length < passwordMinLength) return 'Mínimo de $passwordMinLength caracteres';
  if (!passwordHasUppercase(v)) return 'Inclua ao menos 1 letra maiúscula';
  if (!passwordHasLowercase(v)) return 'Inclua ao menos 1 letra minúscula';
  if (!passwordHasDigit(v)) return 'Inclua ao menos 1 número';
  if (!passwordHasSpecialChar(v)) return 'Inclua ao menos 1 caractere especial (ex.: ! @ # \$)';
  return null;
}

/// Validator pro campo de senha em telas de LOGIN -- só confere que não
/// ficou em branco (a senha em si já foi validada no cadastro; mudar a
/// régua aqui não faz sentido, ver nota acima).
String? validateLoginPassword(String? value) =>
    (value == null || value.isEmpty) ? 'Informe sua senha' : null;
