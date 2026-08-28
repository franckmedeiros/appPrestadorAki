import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'core/auth_controller.dart';
import 'core/biometric_service.dart';
import 'core/notification_service.dart';
import 'core/token_storage.dart';
import 'features/agenda/appointments_repository.dart';
import 'features/customers/customers_repository.dart';
import 'features/marketplace/favorites_controller.dart';
import 'features/marketplace/favorites_repository.dart';
import 'features/marketplace/provider_directory_repository.dart';
import 'features/marketplace/service_requests_repository.dart';
import 'features/notifications/notifications_repository.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';

// O modo padrão do flutter_secure_storage no Android (uma chave RSA no
// Keystore para CADA valor salvo) é conhecido por travar/dar timeout em
// alguns aparelhos — principalmente depois de reinstalar o app várias
// vezes durante o desenvolvimento, quando sobra uma chave "órfã" no
// Keystore de uma instalação anterior. `encryptedSharedPreferences: true`
// troca isso por uma única chave mestra (via Jetpack Security), que é o
// modo recomendado pelo próprio pacote e evita esse travamento.
const _secureStorageAndroidOptions = AndroidOptions(encryptedSharedPreferences: true);

// Aponta o app para os emuladores locais do Firebase (`firebase
// emulators:start`) em vez do projeto real na nuvem — útil durante o
// desenvolvimento, pra não gastar cota nem exigir deploy a cada teste.
// 10.0.2.2 é o endereço especial que o EMULADOR ANDROID usa pra alcançar o
// "localhost" da máquina host (127.0.0.1 não funciona de dentro dele); num
// aparelho físico ou no simulador iOS, troque pelo IP da sua máquina na
// rede local (ex.: --dart-define=FIREBASE_EMULATOR_HOST=192.168.0.10).
// Ative os emuladores com:
//   flutter run --dart-define=USE_FIREBASE_EMULATOR=true
// Sem essa flag (o padrão), o app fala direto com o projeto Firebase de
// verdade — é o que se espera rodando fora do ambiente de desenvolvimento.
const _useFirebaseEmulator =
    bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);
const _emulatorHost =
    String.fromEnvironment('FIREBASE_EMULATOR_HOST', defaultValue: '10.0.2.2');

void main() async {
  // Obrigatório sempre que algo usa canais de plataforma (Firebase, secure
  // storage, local_auth, etc.) antes do runApp() — sem isso, toda chamada
  // nativa feita durante a inicialização falha com "Binding has not yet
  // been initialized".
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Registrado aqui (não dentro de NotificationService.init(), que só
  // roda depois do login) porque o FCM precisa desse handler cadastrado
  // desde o início do processo — mensagens podem chegar com o app
  // fechado, antes de qualquer tela abrir. Ver core/notification_service.dart.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (_useFirebaseEmulator) {
    debugPrint('[Firebase] usando emuladores locais em $_emulatorHost');
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  }

  final authController = AuthController(
    biometricStorage: TokenStorage(
      const FlutterSecureStorage(aOptions: _secureStorageAndroidOptions),
    ),
    biometricService: BiometricService(),
  );
  // Não é aguardado (fire-and-forget de propósito): a SplashScreen fica
  // visível enquanto isso resolve, e o redirect do go_router reage sozinho
  // assim que o AuthController chama notifyListeners() no fim do processo.
  authController.bootstrap();

  runApp(PrestadorAkiApp(authController: authController));
}

class PrestadorAkiApp extends StatefulWidget {
  const PrestadorAkiApp({super.key, required this.authController});

  final AuthController authController;

  @override
  State<PrestadorAkiApp> createState() => _PrestadorAkiAppState();
}

class _PrestadorAkiAppState extends State<PrestadorAkiApp> {
  late final GoRouter _router = buildAppRouter(widget.authController);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.authController),
        // Sem argumentos: cada repositório lê o UID do usuário logado
        // direto do FirebaseAuth.instance.currentUser na hora de montar o
        // caminho no Firestore — só são usados a partir de telas que o
        // redirect do go_router já garante estarem autenticadas (e, no
        // caso das duas primeiras, do lado certo do marketplace).
        Provider(create: (context) => CustomersRepository()),
        Provider(create: (context) => AppointmentsRepository()),
        Provider(create: (context) => ProviderDirectoryRepository()),
        Provider(create: (context) => ServiceRequestsRepository()),
        Provider(create: (context) => FavoritesRepository()),
        Provider(create: (context) => NotificationsRepository()),
        ChangeNotifierProvider(
          create: (context) => FavoritesController(context.read<FavoritesRepository>()),
        ),
      ],
      child: MaterialApp.router(
        title: 'PrestadorAki',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // Sem isso, alguns teclados Android (relatado com Gboard em
        // pt-BR) atropelam a composição de acento/cedilha (ã, ç, é) —
        // o app nunca declarava suportar pt-BR pro sistema. `locale`
        // fixo em vez de deixar o sistema decidir: o app inteiro só
        // existe em português mesmo, não tem tradução pra outro idioma
        // pra alternar.
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _router,
      ),
    );
  }
}
