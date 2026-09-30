/// Valor em reais escrito por extenso — "mil e quinhentos reais".
///
/// Existe por causa do recibo (ver `lib/features/jobs/recibo_pdf.dart`):
/// num recibo brasileiro o valor por extenso não é enfeite, é o que
/// impede que o algarismo seja alterado depois. Recibo sem ele passa por
/// improvisado, e é a primeira coisa que um contador reclama.
///
/// A vírgula entre as ordens ("mil, quinhentos e sessenta e um") é a
/// forma que banco e cartório usam. O "e" só entra antes do último grupo
/// quando ele é menor que cem ou é centena redonda — por isso
/// R$ 1.500,00 sai "mil e quinhentos" e R$ 1.561,00 sai "mil, quinhentos
/// e sessenta e um".
library;

const _unidades = [
  '', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove',
];

/// 10 a 19 não seguem a regra de "dezena + e + unidade" — são nomes
/// próprios, por isso ficam numa lista à parte.
const _dezADezenove = [
  'dez', 'onze', 'doze', 'treze', 'catorze', 'quinze', 'dezesseis',
  'dezessete', 'dezoito', 'dezenove',
];

const _dezenas = [
  '', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta',
  'oitenta', 'noventa',
];

const _centenas = [
  '', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos',
  'seiscentos', 'setecentos', 'oitocentos', 'novecentos',
];

/// Nome de cada grupo de três casas, no singular e no plural. "mil" é
/// invariável, por isso tem tratamento próprio em `_porExtenso`.
const _escalas = [
  ['', ''],
  ['mil', 'mil'],
  ['milhão', 'milhões'],
  ['bilhão', 'bilhões'],
];

/// Um grupo de três casas (1 a 999) por extenso.
String _trio(int n) {
  // "cem" só quando é exatamente 100; 101 em diante é "cento e ...".
  if (n == 100) return 'cem';

  final partes = <String>[];
  final centena = n ~/ 100;
  final resto = n % 100;

  if (centena > 0) partes.add(_centenas[centena]);

  if (resto > 0) {
    if (resto < 10) {
      partes.add(_unidades[resto]);
    } else if (resto < 20) {
      partes.add(_dezADezenove[resto - 10]);
    } else {
      final dezena = resto ~/ 10;
      final unidade = resto % 10;
      partes.add(unidade > 0
          ? '${_dezenas[dezena]} e ${_unidades[unidade]}'
          : _dezenas[dezena]);
    }
  }

  return partes.join(' e ');
}

String _porExtenso(int n) {
  if (n == 0) return 'zero';

  // Quebra em grupos de três casas, do menos pro mais significativo, e
  // depois inverte — é como o número é falado.
  final grupos = <({int valor, int nivel})>[];
  var restante = n;
  var escala = 0;
  while (restante > 0) {
    grupos.add((valor: restante % 1000, nivel: escala));
    restante ~/= 1000;
    escala++;
  }
  final ditos = <({String texto, int valor})>[];
  for (final grupo in grupos.reversed) {
    final valor = grupo.valor;
    if (valor == 0) continue;
    final nivel = grupo.nivel;
    if (nivel == 0) {
      ditos.add((texto: _trio(valor), valor: valor));
    } else if (nivel == 1) {
      // "mil", nunca "um mil".
      ditos.add((texto: valor == 1 ? 'mil' : '${_trio(valor)} mil', valor: valor));
    } else {
      final nome = _escalas[nivel][valor == 1 ? 0 : 1];
      ditos.add((texto: '${_trio(valor)} $nome', valor: valor));
    }
  }

  if (ditos.length == 1) return ditos.first.texto;

  final ultimo = ditos.last;
  final corpo = ditos.sublist(0, ditos.length - 1).map((d) => d.texto).join(', ');
  final ligacao = (ultimo.valor < 100 || ultimo.valor % 100 == 0) ? ' e ' : ', ';
  return '$corpo$ligacao${ultimo.texto}';
}

/// "mil e quinhentos reais", "um real e cinquenta centavos".
///
/// Recebe CENTAVOS, igual ao resto do app (ver `formatCentsBRL`) — usar
/// double pra dinheiro é como um centavo some no arredondamento.
String valorPorExtenso(int cents) {
  final total = cents.abs();
  final reais = total ~/ 100;
  final centavos = total % 100;

  final partes = <String>[];

  if (reais > 0) {
    // "um milhão DE reais" — a preposição só aparece quando o valor
    // termina numa escala redonda. "um milhão reais" é o tipo de erro
    // que salta aos olhos justamente no documento onde não pode.
    final de = (reais >= 1000000 && reais % 1000000 == 0) ? ' de' : '';
    partes.add('${_porExtenso(reais)}$de ${reais == 1 ? 'real' : 'reais'}');
  }

  if (centavos > 0) {
    partes.add(
      '${_porExtenso(centavos)} ${centavos == 1 ? 'centavo' : 'centavos'}',
    );
  }

  if (partes.isEmpty) return 'zero real';
  return partes.join(' e ');
}
