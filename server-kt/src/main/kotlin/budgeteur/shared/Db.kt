package budgeteur.shared

import java.sql.Connection
import java.sql.DriverManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.flywaydb.core.Flyway
import org.jooq.DSLContext
import org.jooq.SQLDialect
import org.jooq.conf.Settings
import org.jooq.impl.DSL

/**
 * The SQLite database. Each unit of work opens its own connection; JDBC blocks,
 * so work runs on the IO dispatcher.
 */
class Db(val url: String) {
    fun open(): Connection =
        DriverManager.getConnection(url).also { connection ->
            // SQLite enforces foreign keys per connection.
            connection.createStatement().use { it.execute("PRAGMA foreign_keys = ON") }
        }

    /** Runs jOOQ queries over one connection. */
    suspend fun <T> sql(work: DSLContext.() -> T): T =
        withContext(Dispatchers.IO) {
            open().use { DSL.using(it, SQLDialect.SQLITE, settings).work() }
        }

    /** Applies pending migrations from `db/migration` and returns how many ran. */
    fun migrate(): Int {
        val result = Flyway.configure().dataSource(url, null, null).load().migrate()
        // WAL is stored in the file, so setting it once covers later connections.
        open().use { c -> c.createStatement().use { it.execute("PRAGMA journal_mode = WAL") } }
        return result.migrationsExecuted
    }

    private companion object {
        init {
            // jOOQ logs a banner and usage tips on first use.
            System.setProperty("org.jooq.no-logo", "true")
            System.setProperty("org.jooq.no-tips", "true")
        }

        val settings: Settings = Settings().withExecuteLogging(false)
    }
}
