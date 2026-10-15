/// TRAVA DE CONTATO (decisão do Franck, 14/10): enquanto o prestador não
/// tem assinatura paga (ex.: teste liberado pelo hub), ele conversa com o
/// cliente só pelo chat do app — telefone, WhatsApp e e-mail digitados nas
/// mensagens aparecem mascarados, e os botões de WhatsApp do cliente ficam
/// escondidos. Assim o contato direto (que é o que tem valor) só vem com a
/// assinatura, e ninguém combina "me chama no zap" pra sair do app.
///
/// Quem decide se o contato está liberado é `AuthController.contatoClienteLiberado`.
library;

/// Texto mostrado no lugar de um contato escondido.
const String kContatoOculto = '•••••';

/// Explicação curta pra mostrar onde o contato ficaria.
const String kAvisoContatoBloqueado =
    'O contato direto do cliente é liberado com a assinatura. Até lá, converse pelo chat do app.';

// Sequência com 9+ dígitos, aceitando separadores comuns entre eles:
// "(48) 99912-3456", "48 9 9912 3456", "+55 48 999123456".
// 9 e não 8 de propósito: datas ("15/10/2026", "15-10-2026") e CEP têm 8
// dígitos e apareceriam mascarados à toa numa conversa de orçamento.
final RegExp _telefone = RegExp(r'\(?(?:\+?\d[\s().\-]*){9,}');
final RegExp _email = RegExp(r'[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+');
// Número escrito por extenso ou com letras no meio ("nove nove nove...")
// fica de fora de propósito: pegar tudo é impossível, e o objetivo é só
// tirar o caminho fácil.

/// Troca telefones e e-mails por [kContatoOculto].
String mascararContatos(String texto) {
  return texto
      .replaceAllMapped(_email, (_) => kContatoOculto)
      .replaceAllMapped(_telefone, (m) {
        // Preserva o espaço final que a regex engole, pra não colar palavras.
        final s = m.group(0)!;
        return s.endsWith(' ') ? '$kContatoOculto ' : kContatoOculto;
      });
}

/// `true` se o texto tem algo que seria mascarado.
bool temContato(String texto) => _telefone.hasMatch(texto) || _email.hasMatch(texto);
