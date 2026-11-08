plugins {
    kotlin("jvm") version "2.2.21"
    kotlin("plugin.serialization") version "2.2.21"
    application
}

group = "budgeteur"
version = "0.1.0"

repositories { mavenCentral() }

val ktor = "3.3.1"
val arrow = "2.1.2"

dependencies {
    implementation("io.ktor:ktor-server-core:$ktor")
    implementation("io.ktor:ktor-server-netty:$ktor")
    implementation("io.ktor:ktor-server-auth:$ktor")
    implementation("io.ktor:ktor-server-auth-jwt:$ktor")
    implementation("io.arrow-kt:arrow-core:$arrow")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.xerial:sqlite-jdbc:3.50.3.0")
    implementation("ch.qos.logback:logback-classic:1.5.18")

    testImplementation(kotlin("test"))
    testImplementation("io.ktor:ktor-server-test-host:$ktor")
}

kotlin { jvmToolchain(21) }

application { mainClass.set("budgeteur.MainKt") }

tasks.test { useJUnitPlatform() }

// The F# server owns the migrations. Both servers read the same files and the
// same DbUp journal, so either can run against the same database.
val migrationsDir = layout.projectDirectory.dir("../server/src/Budgeteur/Data/Migrations")

tasks.processResources {
    from(migrationsDir) { into("migrations") }
    // A jar cannot list its own directories, so record the scripts in order.
    val index = migrationsDir.asFileTree.matching { include("*.sql") }
    inputs.files(index)
    doLast {
        val out = destinationDir.resolve("migrations/index.txt")
        out.parentFile.mkdirs()
        out.writeText(index.files.map { it.name }.sorted().joinToString("\n"))
    }
}

// GetStatus reports this as the running version.
tasks.jar { manifest { attributes("Implementation-Version" to project.version) } }
