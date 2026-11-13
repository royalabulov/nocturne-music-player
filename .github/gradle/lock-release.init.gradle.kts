// CI only (see ci.yml): Gradle keeps no lockfile unless asked, so osv-scanner had nothing to
// read for the Android side. With this, `:app:dependencies --write-locks` writes
// android/app/gradle.lockfile with every library that goes into the release app and its exact
// version. Only releaseRuntimeClasspath: lint and test tools (netty, bouncycastle, ...) never
// ship, and their advisories would only be noise. Not used by local builds, so a Flutter
// upgrade never fails on a stale lock.
allprojects {
    if (path == ":app") {
        configurations.matching { it.name == "releaseRuntimeClasspath" }.configureEach {
            resolutionStrategy.activateDependencyLocking()
        }
    }
}
