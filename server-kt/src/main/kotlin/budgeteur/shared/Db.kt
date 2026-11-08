package budgeteur.shared

import javax.sql.DataSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.flywaydb.core.Flyway
import org.jooq.DSLContext
import org.jooq.SQLDialect
import org.jooq.conf.Settings
import org.jooq.impl.DSL
import org.sqlite.SQLiteConfig
import org.sqlite.SQLiteDataSource

/**
 * The SQLite database. Every connection gets the same settings from the data source. JDBC blocks,
 * so work runs on the IO dispatcher.
 */
class Db(url: String) {
    val dataSource: DataSource =
        SQLiteDataSource(
                SQLiteConfig().apply {
                    enforceForeignKeys(true)
                    setJournalMode(SQLiteConfig.JournalMode.WAL)
                    // A transaction takes the write lock when it begins, so a check
                    // it makes before writing cannot be invalidated by another
                    // writer. A second writer waits for the lock rather than failing.
                    setTransactionMode(SQLiteConfig.TransactionMode.IMMEDIATE)
                    setBusyTimeout(5_000)
                }
            )
            .also { it.url = url }

    private val dsl = DSL.using(dataSource, SQLDialect.SQLITE, settings)

    /** Runs queries that each commit on their own. */
    suspend fun <T> sql(work: DSLContext.() -> T): T = withContext(Dispatchers.IO) { dsl.work() }

    /** Runs [work] in one transaction, which rolls back if it throws, including when it raises. */
    suspend fun <T> transaction(work: DSLContext.() -> T): T =
        withContext(Dispatchers.IO) { dsl.transactionResult { tx -> tx.dsl().work() } }

    /** Applies pending migrations from `db/migration` and returns how many ran. */
    fun migrate(): Int =
        Flyway.configure().dataSource(dataSource).load().migrate().migrationsExecuted

    private companion object {
        init {
            // jOOQ logs a banner and usage tips on first use.
            System.setProperty("org.jooq.no-logo", "true")
            System.setProperty("org.jooq.no-tips", "true")
        }

        val settings: Settings = Settings().withExecuteLogging(false)
    }
}
