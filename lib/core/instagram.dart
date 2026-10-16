/// Instagram do prestador: o que a pessoa digita vira só o nome de usuário.
///
/// Aceita "@fulano", "fulano", "instagram.com/fulano",
/// "https://www.instagram.com/fulano/?igsh=..." — tudo vira "fulano".
/// Devolve null se ficar vazio, e lança [FormatException] se não for um
/// nome de usuário válido (letras, números, ponto e sublinhado, até 30).
String? normalizarInstagram(String? bruto) {
  var t = (bruto ?? '').trim();
  if (t.isEmpty) return null;
  final url = RegExp(r'instagram\.com/([^/?#\s]+)', caseSensitive: false).firstMatch(t);
  if (url != null) t = url.group(1)!;
  t = t.replaceFirst(RegExp(r'^@+'), '').trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(t)) {
    throw const FormatException('Use só o nome de usuário, ex.: @seuperfil');
  }
  return t.toLowerCase();
}

/// Validador pro TextFormField.
String? validarInstagram(String? valor) {
  try {
    normalizarInstagram(valor);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// Link do perfil: https://instagram.com/fulano
Uri linkInstagram(String usuario) => Uri.https('instagram.com', '/$usuario');
