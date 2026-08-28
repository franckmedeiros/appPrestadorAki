plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
