import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

// ✅ Root-level Gradle build file for Kotlin DSL projects

plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android")  apply false
    id("com.google.gms.google-services")  apply false
}

// ✅ Central repositories
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ✅ Move build outputs to shared /build folder
val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}

// ✅ Force app project to evaluate first
subprojects {
    project.evaluationDependsOn(":app")
}

// ✅ Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
