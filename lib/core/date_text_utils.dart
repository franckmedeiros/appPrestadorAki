import 'package:flutter/material.dart';

/// Formata/interpreta datas e horas digitadas nos campos que substituíram
/// os botões de abrir calendário/relógio em algumas telas (ver
/// AppointmentFormScreen e RequestQuoteFormScreen) — decisão combinada
/// com o Franck: mais rápido digitar "15/03/2027" do que abrir um
/// seletor, principalmente pra quem já sabe a data de cor. Usado junto
/// com `MaskTextInputFormatter('##/##/####')` (data) ou
/// `MaskTextInputFormatter('##:##')` (hora) — essas funções só cuidam da
/// formatação/leitura, a máscara cuida de guiar a digitação.
String formatDateDdMmYyyy(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String formatTimeHhMm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// Devolve `null` se o texto não é uma data completa e válida — tanto pra
/// quando ainda está no meio da digitação ("15/03/20") quanto pra uma
/// data que não existe de verdade (ex.: 31/02/2027).
DateTime? tryParseDateDdMmYyyy(String text) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text);
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  // DateTime normaliza datas fora do intervalo em vez de lançar erro (ex.:
  // dia 31 de fevereiro vira 3 de março) — comparar os campos de volta
  // depois de construir é o jeito de perceber isso e tratar como inválido.
  final date = DateTime(year, month, day);
  if (date.day != day || date.month != month || date.year != year) return null;
  return date;
}

/// Mesma ideia de `tryParseDateDdMmYyyy`, pro campo de hora ("HH:mm").
TimeOfDay? tryParseTimeHhMm(String text) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}
