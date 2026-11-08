package budgeteur.shared

import java.sql.Connection
import java.sql.DriverManager
import java.sql.PreparedStatement
import java.sql.ResultSet
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Opens a connection per unit of work, as the F# server's QueryContextFactory
 * does. JDBC blocks, so work runs on the IO dispatcher.
 */
class Db(val url: String) {
    fun open(): Connection =
        DriverManager.getConnection(url).also { connection ->
            // SQLite enforces foreign keys per connection.
            connection.createStatement().use { it.execute("PRAGMA foreign_keys = ON") }
        }

    suspend fun <T> run(work: (Connection) -> T): T =
        withContext(Dispatchers.IO) { open().use(work) }
}

/**
 * GUIDs are stored as uppercase TEXT, the format Microsoft.Data.Sqlite writes,
 * so both servers can share a database.
 */
fun UUID.toDb(): String = toString().uppercase()

fun ResultSet.uuid(column: String): UUID = UUID.fromString(getString(column))

private fun PreparedStatement.bind(params: List<Any?>) =
    params.forEachIndexed { i, param ->
        when (param) {
            is UUID -> setString(i + 1, param.toDb())
            else -> setObject(i + 1, param)
        }
    }

fun <T> Connection.query(sql: String, vararg params: Any?, row: (ResultSet) -> T): List<T> =
    prepareStatement(sql).use { statement ->
        statement.bind(params.toList())
        statement.executeQuery().use { rs ->
            buildList { while (rs.next()) add(row(rs)) }
        }
    }

fun Connection.count(sql: String, vararg params: Any?): Int =
    query(sql, *params) { it.getInt(1) }.single()

/** Returns the number of rows affected. */
fun Connection.execute(sql: String, vararg params: Any?): Int =
    prepareStatement(sql).use { statement ->
        statement.bind(params.toList())
        statement.executeUpdate()
    }
