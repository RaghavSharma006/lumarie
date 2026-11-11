allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = "https://jitpack.io")
    }
}

// The Flutter esp_provisioning_wifi 0.3.1 plugin hardcodes Espressif
// esp-idf-provisioning-android lib-2.1.2 (pre Security2 sec_patch_ver).
// Our EE04 BLE Security2 firmware uses the newer session protocol. Override
// the transitive native library with 2.2.3, the first patch-aware version
// with Android API 34 compatibility. Later lib-2.4.4 pulls CameraX 1.5.1
// which needs API 35+, breaking this Flutter plugin's Android build.
// This does NOT lower or disable frame authentication.
subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (
                requested.group == "com.github.espressif" &&
                requested.name == "esp-idf-provisioning-android"
            ) {
                useVersion("lib-2.2.3")
                because("Security2 sec_patch_ver compatibility; lib-2.1.2 cannot interpret the newer BLE session metadata")
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
