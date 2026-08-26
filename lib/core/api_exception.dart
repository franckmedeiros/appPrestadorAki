/// Erro de API com a mensagem já pronta para mostrar ao usuário — o backend
/// (NestJS + class-validator) devolve `{ message, statusCode }` nas respostas
/// de erro, então repassamos essa mensagem diretamente.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
