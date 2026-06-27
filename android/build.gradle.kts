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

// بعض الإضافات (مثل file_picker) تبقى على compileSdk 34 ولا يرفعها Flutter،
// بينما تبعية flutter_plugin_android_lifecycle تتطلب 36. نفرض 36 على كل
// وحدات الإضافات عبر الانعكاس (بدون الحاجة لاستيراد أنواع AGP).
subprojects {
    val forceCompileSdk = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            runCatching {
                androidExt.javaClass.methods
                    .firstOrNull {
                        it.name == "compileSdkVersion" &&
                            it.parameterTypes.size == 1 &&
                            it.parameterTypes[0] == Int::class.javaPrimitiveType
                    }
                    ?.invoke(androidExt, 36)
            }
            Unit
        }
    }
    // إن كان المشروع قد قُيِّم مسبقًا (مثل :app) نضبطه مباشرة، وإلا بعد التقييم.
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
