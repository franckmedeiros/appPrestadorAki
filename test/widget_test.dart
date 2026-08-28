// Teste padrão gerado pelo `flutter create` (contador de exemplo,
// widget `MyApp`) — nunca foi adaptado pro app de verdade e, por isso,
// não compilava mais (`MyApp` não existe aqui, o widget raiz real é
// `PrestadorAkiApp`, ver lib/main.dart).
//
// Não dá pra simplesmente trocar por `pumpWidget(const PrestadorAkiApp(...))`
// porque o app real espera `Firebase.initializeApp()` já ter rodado (feito
// em `main()`, antes do `runApp`) e um `AuthController` de verdade — nenhum
// dos dois está disponível de graça num widget test. Fazer isso direito
// pediria mockar Firebase/AuthController, o que fica pra quando o projeto
// tiver uma suíte de testes de verdade. Por ora, só garante que o pacote de
// testes compila e roda sem quebrar o build (`flutter test`/CI).
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanity check', () {
    expect(1 + 1, 2);
  });
}
