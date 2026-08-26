import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_exception.dart';

/// Cliente HTTP fino para a API do PrestadorAki (contrato em openapi.yaml).
///
/// Não conhece nada de autenticação além de "pegar o token atual" e "pedir
/// para renovar quando um 401 chega" — essas duas pontas são conectadas
/// pelo AuthController na inicialização do app, evitando um import
/// circular entre as duas classes.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  /// Ex.: http://10.0.2.2:3000/v1 no emulador Android apontando para a API
  /// rodando localmente na máquina host (127.0.0.1 não funciona no emulador).
  final String baseUrl;
  final http.Client _client;

  String? Function()? tokenProvider;
  Future<bool> Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final token = tokenProvider?.call();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final response = await _request(method, uri, headers, body);

    if (response.statusCode == 401 && !retried && onUnauthorized != null) {
      final refreshed = await onUnauthorized!();
      if (refreshed) {
        return _send(method, path, query: query, body: body, retried: true);
      }
    }

    return _parse(response);
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    final encodedBody = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return _client.put(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return _client.delete(uri, headers: headers);
      default:
        throw ArgumentError('Método HTTP não suportado: $method');
    }
  }

  dynamic _parse(http.Response response) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    final hasBody = response.body.isNotEmpty;
    final decoded = hasBody ? jsonDecode(response.body) : null;

    if (!isSuccess) {
      final message = (decoded is Map && decoded['message'] != null)
          ? decoded['message'].toString()
          : 'Erro inesperado (HTTP ${response.statusCode}).';
      throw ApiException(response.statusCode, message);
    }

    return decoded;
  }
}
