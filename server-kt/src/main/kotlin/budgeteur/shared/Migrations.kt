package budgeteur.shared

import java.sql.Connection

/**
 * Applies the F# server's migration scripts and records them in DbUp's journal
 * table under DbUp's script names, so the two servers agree on what has run.
 */
object Migrations {
    private const val NAME_PREFIX = "Budgeteur.Data.Migrations."

    private fun resource(path: String): String =
        checkNotNull(Migrations::class.java.getResource("/migrations/$path")) {
            "Missing migration resource $path"
        }.readText()

    private fun scripts(): List<String> =
        resource("index.txt").lines().filter { it.isNotBlank() }

    private fun ensureJournal(connection: Connection) {
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS SchemaVersions (
                SchemaVersionID INTEGER CONSTRAINT 'PK_SchemaVersions_SchemaVersionID' PRIMARY KEY AUTOINCREMENT NOT NULL,
                ScriptName TEXT NOT NULL,
                Applied DATETIME NOT NULL
            )
            """.trimIndent(),
        )
    }

    private fun applied(connection: Connection): Set<String> =
        connection.query("SELECT ScriptName FROM SchemaVersions") { it.getString(1) }.toSet()

    /** One transaction per script: a script that fails partway leaves the schema as it was. */
    private fun apply(connection: Connection, file: String) {
        connection.autoCommit = false
        try {
            // sqlite-jdbc runs every statement in the string.
            connection.createStatement().use { it.executeUpdate(resource(file)) }
            connection.execute(
                "INSERT INTO SchemaVersions (ScriptName, Applied) VALUES (?, datetime('now'))",
                NAME_PREFIX + file,
            )
            connection.commit()
        } catch (e: Exception) {
            connection.rollback()
            throw IllegalStateException("Migration $file failed", e)
        } finally {
            connection.autoCommit = true
        }
    }

    /** Returns the scripts it applied. */
    fun run(db: Db): List<String> =
        db.open().use { connection ->
            ensureJournal(connection)
            val done = applied(connection)
            val pending = scripts().filterNot { (NAME_PREFIX + it) in done }
            pending.forEach { apply(connection, it) }
            // WAL is stored in the file, so setting it once covers later connections.
            connection.createStatement().use { it.execute("PRAGMA journal_mode = WAL") }
            pending
        }
}
