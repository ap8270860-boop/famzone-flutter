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

    /*
     * Force every plugin module up to the app's compileSdk.
     *
     * Some plugins pin an older one in their own build file. Gradle then
     * refuses to link a library compiled against 34 into a project whose
     * other dependencies demand 36, and the build dies in
     * checkDebugAarMetadata naming two plugins that have nothing to do with
     * each other.
     *
     * Registered here rather than in a block of its own, because the
     * evaluationDependsOn(":app") below forces :app to evaluate — and
     * afterEvaluate cannot be added to a project that has already been
     * evaluated. Ordering in this file is load-bearing.
     *
     * afterEvaluate specifically, not plugins.withId: the module's own
     * build file sets its compileSdk during evaluation, so anything earlier
     * would simply be overwritten.
     *
     * Reflection rather than a typed cast, because the Android extension
     * class and its generic arity have both moved between AGP versions.
     * runCatching keeps a module without that setter from failing the build.
     */
    afterEvaluate {
        val androidExtension = extensions.findByName("android")

        if (androidExtension != null) {
            androidExtension.javaClass.methods
                .filter { it.name == "setCompileSdk" && it.parameterCount == 1 }
                .forEach { setter -> runCatching { setter.invoke(androidExtension, 36) } }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
