import com.github.benmanes.gradle.versions.updates.DependencyUpdatesTask
import org.flywaydb.core.Flyway

buildscript {
    // The build runs the migrations itself to give jOOQ a schema to read.
    dependencies {
        classpath(libs.flyway.core)
        classpath(libs.sqlite.jdbc)
    }
}

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.jooq.codegen)
    alias(libs.plugins.ktfmt)
    alias(libs.plugins.detekt)
    alias(libs.plugins.versions)
    alias(libs.plugins.version.catalog.update)
    alias(libs.plugins.cyclonedx)
    application
}

group = "budgeteur"

// The image build passes the release version and commit, as `just publish` does for the F#
// server: `gradle installDist -PappVersion=1.2.3 -PgitSha=abc123`.
version = providers.gradleProperty("appVersion").getOrElse("0.0.0-local")

val gitSha = providers.gradleProperty("gitSha").getOrElse("")

repositories { mavenCentral() }

dependencies {
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.netty)
    implementation(libs.ktor.server.auth)
    implementation(libs.ktor.server.body.limit)
    implementation(libs.ktor.server.auth.jwt)
    implementation(libs.ktor.server.sessions)
    implementation(libs.ktor.server.routing.openapi)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.ktor.server.status.pages)
    implementation(libs.arrow.core)
    implementation(libs.nimbus.oidc)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.sqlite.jdbc)
    implementation(libs.flyway.core)
    implementation(libs.jooq)
    implementation(libs.jooq.kotlin)
    implementation(libs.logback.classic)
    implementation(libs.logstash.logback.encoder)
    implementation(platform(libs.jackson3.bom))
    implementation(platform(libs.jackson2.bom))
    constraints { implementation(libs.guava) }

    jooqCodegen(libs.sqlite.jdbc)

    testImplementation(kotlin("test"))
    testImplementation(libs.ktor.server.test.host)
}

// `just kt-outdated` and `just kt-update` offer a pre-release only in place of a pre-release.
fun isStable(version: String) =
    !Regex("(?i)alpha|beta|rc|-m\\d|eap|snapshot").containsMatchIn(version)

tasks.withType<DependencyUpdatesTask> {
    // The dev shell provides Gradle.
    checkForGradleUpdate = false
    rejectVersionIf { !isStable(candidate.version) && isStable(currentVersion) }
}

kotlin {
    jvmToolchain(21)
    // Route.describe, which documents an endpoint in the OpenAPI document.
    compilerOptions { optIn.add("io.ktor.utils.io.ExperimentalKtorApi") }
}

// The Kotlin coding conventions: four-space indents, 100 columns.
ktfmt { kotlinLangStyle() }

detekt { config.setFrom("detekt.yml") }

application { mainClass.set("budgeteur.MainKt") }

tasks.test { useJUnitPlatform() }

// jOOQ generates the table classes from the schema the migrations produce. The
// build migrates a scratch SQLite database with Flyway, as the server does at
// startup, so codegen sees the same schema the server runs against. The
// generated code is a build output, rebuilt whenever a migration changes.
val migrations = layout.projectDirectory.dir("src/main/resources/db/migration")
val codegenSchema = layout.buildDirectory.file("codegen/schema.sqlite3")
val generatedJooq = layout.buildDirectory.dir("generated-sources/jooq")

val migrateCodegenSchema by tasks.registering {
    inputs.dir(migrations)
    outputs.file(codegenSchema)
    doLast {
        val file = codegenSchema.get().asFile
        file.parentFile.mkdirs()
        file.delete()
        Flyway.configure(Flyway::class.java.classLoader)
            .dataSource("jdbc:sqlite:${file.absolutePath}", null, null)
            .locations("filesystem:${migrations.asFile.absolutePath}")
            .load()
            .migrate()
    }
}

jooq {
    configuration {
        jdbc {
            driver = "org.sqlite.JDBC"
            url = "jdbc:sqlite:${codegenSchema.get().asFile.absolutePath}"
        }
        generator {
            name = "org.jooq.codegen.KotlinGenerator"
            database {
                name = "org.jooq.meta.sqlite.SQLiteDatabase"
                excludes = "flyway_schema_history|sqlite_.*"
            }
            generate {
                isRecords = true
                isPojos = false
                isDaos = false
                isKotlinNotNullRecordAttributes = true
            }
            target {
                packageName = "budgeteur.data.db"
                directory = generatedJooq.get().asFile.absolutePath
            }
        }
    }
}

tasks.named("jooqCodegen") {
    dependsOn(migrateCodegenSchema)
    inputs.file(codegenSchema)
    outputs.dir(generatedJooq)
}

sourceSets.main { kotlin.srcDir(generatedJooq) }

tasks.compileKotlin { dependsOn("jooqCodegen") }

// GetStatus reports this as the running version: `1.2.3+abc123`, as the F# server reports its
// informational version.
tasks.jar {
    val implementationVersion = if (gitSha.isEmpty()) "$version" else "$version+$gitSha"
    manifest { attributes("Implementation-Version" to implementationVersion) }
}

// `just audit` scans this SBOM: what the server runs with, not the build's own tooling.
tasks.cyclonedxDirectBom { includeConfigs.set(listOf("runtimeClasspath")) }
