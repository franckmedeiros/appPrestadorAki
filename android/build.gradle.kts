allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Correção pro erro real de compileSdk: NÃO era o compileSdk do nosso
// próprio app (esse já estava em 36 desde o primeiro fix) — é o módulo
// Android interno do plugin `geocoding` (":geocoding_android"), que vem
// com o PRÓPRIO compileSdk fixo em 33 dentro do código-fonte do pacote
// (baixado do pub.dev, fora do nosso controle). Mudar o compileSdk do
// nosso app não alcança isso — cada módulo Gradle (inclusive os que vêm
// de dependências/plugins) declara o dele. Isso força TODOS os
// subprojetos Android (o app e qualquer plugin, presente ou futuro) a
// compilar contra pelo menos a versão 36, sem precisar esperar o autor
// do pacote publicar uma atualização.
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.let { android ->
            val current = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (current < 36) {
                android.compileSdkVersion(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
