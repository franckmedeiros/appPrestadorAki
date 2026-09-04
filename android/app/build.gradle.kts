import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Assinatura de release de verdade (ver https://flutter.dev/to/reference-keystore)
// — sem isso, o build de release usava a chave de DEBUG (placeholder do
// template do Flutter), que o Google Play recusa pra qualquer upload.
// `android/key.properties` + `android/upload-keystore.jks` nunca são
// commitados (ver android/.gitignore) — no Codemagic, esses dois arquivos
// são reconstituídos a partir de um "Android keystore" configurado em
// Team settings > Code signing identities antes do build rodar (ver
// workflow `android-release` em codemagic.yaml).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.opoutsourcing.prestadoraki"
    // Travado em 36 (em vez de usar flutter.compileSdkVersion, que essa
    // versao do Flutter resolve pra um valor mais baixo sozinha): os
    // plugins geocoding_android e suas dependencias
    // (androidx.annotation-experimental, exifinterface) exigem
    // compileSdk >= 34 pra compilar. Isso so afeta contra qual versao da
    // API o app e COMPILADO - nao muda minSdk (quais aparelhos
    // instalam). `targetSdk`, abaixo, tambem passou a ser travado em 36
    // pelo mesmo motivo prático (exigência da Play Console) — ver o
    // comentário dele.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Exigido pelo flutter_local_notifications (usa APIs de java.time
        // via desugaring — ver core/notification_service.dart) desde que
        // ele entrou no projeto pra central de notificações. Sem isso, o
        // build de release falha com "requires core library desugaring
        // to be enabled". A versão da lib de desugar fica no bloco
        // `dependencies` no fim deste arquivo.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.opoutsourcing.prestadoraki"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Travado em 36 (Android 16), mesma razão prática do `compileSdk`
        // acima: a Play Console passou a EXIGIR targetSdk 36 a partir de
        // 30/ago/2026 pra continuar aceitando atualizações do app (prazo
        // avisado no "Status da política" do Play Console) — a versão do
        // Flutter instalada aqui ainda resolve `flutter.targetSdkVersion`
        // pra 35 sozinha, então força-se o valor explícito em vez de
        // esperar por um upgrade do Flutter.
        //
        // Ressalva importante: isso muda comportamento de verdade em
        // tempo de execução (não é só uma flag de build), então vale
        // testar o app rodando num aparelho/emulador Android 16 antes de
        // publicar — early rollout no Play Console, ou pelo menos os
        // fluxos principais (login, busca, agenda, notificações) na mão.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // No Codemagic (workflow `android-release`), o keystore vem do
    // `android_signing` do YAML — Codemagic injeta o arquivo e as 4
    // variáveis abaixo sozinho, NUNCA lê `key.properties` (esse é só pra
    // build local, na sua máquina). Local tem prioridade pro
    // key.properties se por acaso as duas coisas existirem ao mesmo
    // tempo (não deveria, mas evita ambiguidade).
    val cmKeystorePath = System.getenv("CM_KEYSTORE_PATH")
    val hasReleaseSigning = hasKeystoreProperties || cmKeystorePath != null

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                if (hasKeystoreProperties) {
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    // `rootProject.file(...)` (não `file(...)`) é o que importa
                    // aqui: o valor gravado em key.properties é só o NOME do
                    // arquivo ("upload-keystore.jks", sem pasta), e dentro do
                    // build.gradle.kts do módulo :app um `file(...)` sozinho
                    // resolve relativo a android/app/ (onde o keystore NÃO
                    // está), não a android/ (onde ele está de verdade) — foi
                    // exatamente esse descompasso que deu "Keystore file ...
                    // not found" no primeiro build de release do Franck.
                    storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                } else {
                    keyAlias = System.getenv("CM_KEY_ALIAS")
                    keyPassword = System.getenv("CM_KEY_PASSWORD")
                    storeFile = file(cmKeystorePath!!)
                    storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                }
            }
        }
    }

    buildTypes {
        release {
            // Sem key.properties NEM variáveis CM_* (ex.: clone novo da
            // máquina de alguém, sem o keystore) cai pra chave de debug,
            // só pra `flutter run --release`/`flutter build apk --debug`
            // continuarem funcionando localmente sem configuração
            // nenhuma — build de release de VERDADE (o que vai pro Play
            // Console) só sai assinado certo com um dos dois.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Par do `isCoreLibraryDesugaringEnabled = true` acima.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
