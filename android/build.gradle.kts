val androidBuildToolsVersion = "36.1.0"

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

fun configureAndroidBuildTools(project: Project) {
    project.extensions.findByName("android")?.let { androidExtension ->
        androidExtension.javaClass.methods
            .firstOrNull { method ->
                method.name == "setBuildToolsVersion" && method.parameterCount == 1
            }
            ?.invoke(androidExtension, androidBuildToolsVersion)
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    pluginManager.withPlugin("com.android.application") {
        configureAndroidBuildTools(this@subprojects)
    }
    pluginManager.withPlugin("com.android.library") {
        configureAndroidBuildTools(this@subprojects)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
