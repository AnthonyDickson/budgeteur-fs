import org.flywaydb.core.Flyway

buildscript {
    // The build runs the migrations itself to give jOOQ a schema to read.
    dependencies {
        classpath("org.flywaydb:flyway-core:13.12.1")
        classpath("org.xerial:sqlite-jdbc:3.54.1.0")
    }
}

plugins {
    kotlin("jvm") version "2.4.21"
    kotlin("plugin.serialization") version "2.4.21"
    id("org.jooq.jooq-codegen-gradle") version "3.21.9"
    id("com.ncorti.ktfmt.gradle") version "0.27.0"
    id("dev.detekt") version "2.0.0-alpha.6"
    application
}

group = "budgeteur"

version = "0.1.0"

repositories { mavenCentral() }

val ktor = "3.6.1"
val arrow = "2.3.0"
val jooq = "3.21.9"
val sqliteJdbc = "3.54.1.0"

dependencies {
    implementation("io.ktor:ktor-server-core:$ktor")
    implementation("io.ktor:ktor-server-netty:$ktor")
    implementation("io.ktor:ktor-server-auth:$ktor")
    implementation("io.ktor:ktor-server-body-limit:$ktor")
    implementation("io.ktor:ktor-server-auth-jwt:$ktor")
    implementation("io.ktor:ktor-server-sessions:$ktor")
    implementation("io.ktor:ktor-server-routing-openapi:$ktor")
    implementation("io.ktor:ktor-server-content-negotiation:$ktor")
    implementation("io.ktor:ktor-serialization-kotlinx-json:$ktor")
    implementation("io.ktor:ktor-server-status-pages:$ktor")
    implementation("io.arrow-kt:arrow-core:$arrow")
    implementation("com.nimbusds:oauth2-oidc-sdk:11.38.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    implementation("org.xerial:sqlite-jdbc:$sqliteJdbc")
    implementation("org.flywaydb:flyway-core:13.12.1")
    implementation("org.jooq:jooq:$jooq")
    implementation("org.jooq:jooq-kotlin:$jooq")
    implementation("ch.qos.logback:logback-classic:1.6.6")
    implementation("net.logstash.logback:logstash-logback-encoder:9.0")

    jooqCodegen("org.xerial:sqlite-jdbc:$sqliteJdbc")

    testImplementation(kotlin("test"))
    testImplementation("io.ktor:ktor-server-test-host:$ktor")
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

// GetStatus reports this as the running version.
tasks.jar { manifest { attributes("Implementation-Version" to project.version) } }
