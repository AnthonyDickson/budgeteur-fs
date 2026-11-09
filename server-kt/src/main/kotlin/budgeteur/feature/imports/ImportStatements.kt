@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.imports

import arrow.core.raise.context.bind
import arrow.core.raise.context.ensure
import arrow.core.raise.context.withError
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.data.readRules
import budgeteur.data.recordBalance
import budgeteur.data.saveCategorisation
import budgeteur.data.toAccount
import budgeteur.data.toRecord
import budgeteur.domain.Account
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.UuidSerializer
import budgeteur.shared.bodyLimit
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.newId
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.jsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.describe
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import org.jooq.DSLContext

@Serializable
@JsonSchema.Description("A CSV file, read as UTF-8 text by the client.")
data class ImportFileRequest(
    @JsonSchema.Description("The file's name, used in error messages.") val name: String,
    @JsonSchema.Description("The file's text.") val content: String,
)

@Serializable
@JsonSchema.Description("Payload for importing bank statements.")
data class ImportRequest(
    @JsonSchema.Description("One statement per file.")
    @JsonSchema.MinItems(1)
    val files: List<ImportFileRequest>
)

@Serializable
@JsonSchema.Description(
    "An account the import created for a statement whose account number the user had no " +
        "account for."
)
data class CreatedAccountResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(
        "The account number, followed by the product name when the statement gives one."
    )
    val name: String,
    @JsonSchema.Description("The account number in canonical form.") val number: String,
)

@Serializable
@JsonSchema.Description("What the import did.")
data class ImportResponse(
    @JsonSchema.Description("Rows inserted as transactions, transfers included.") val imported: Int,
    @JsonSchema.Description("Rows already imported, or repeated within the request.")
    val skippedDuplicates: Int,
    @JsonSchema.Description(
        "Imported rows between the user's own accounts, marked as transfers and left untagged."
    )
    val transfers: Int,
    @JsonSchema.Description("Imported rows a rule tagged.") val taggedByRules: Int,
    @JsonSchema.Description("The accounts the import created.")
    val accountsCreated: List<CreatedAccountResponse>,
)

/**
 * The request body limit for this endpoint: a year of statements fits, and it matches nginx's
 * default `client_max_body_size`. Every other endpoint keeps the default. See decision 10 in
 * docs/csv-import.md.
 */
const val IMPORT_BODY_LIMIT: Long = 1024 * 1024

/**
 * Imports the statements in one IMMEDIATE transaction, so a concurrent import cannot insert the
 * same hashes between the check and the write: finds or creates each statement's account, drops
 * duplicates, marks transfers, inserts the transactions with their rule tags, and records the
 * balance observations. See decision 8 in docs/csv-import.md.
 */
private fun DSLContext.import(
    userId: String,
    statements: List<Statement>,
): Pair<ImportCounts, List<Account>> {
    val accounts = selectFrom(ACCOUNTS).where(ACCOUNTS.USER_ID.eq(userId)).fetch { it.toAccount() }
    val created =
        missingAccounts(accounts.mapNotNull { it.number }.toSet(), statements).map {
            createAccount(newId(), it)
        }
    created.forEach { insertInto(ACCOUNTS).set(it.toRecord(userId)).execute() }

    val accountIds =
        (accounts + created)
            .mapNotNull { account -> account.number?.let { it to account.id } }
            .toMap()
    val hashes =
        select(TRANSACTIONS.IMPORT_HASH)
            .from(TRANSACTIONS)
            .where(TRANSACTIONS.USER_ID.eq(userId), TRANSACTIONS.IMPORT_HASH.isNotNull)
            .fetchSet(TRANSACTIONS.IMPORT_HASH)
            .filterNotNull()
            .toSet()

    val (transactions, counts) = plan(::newId, accountIds, hashes, readRules(userId), statements)
    transactions.forEach {
        insertInto(TRANSACTIONS).set(it.transaction.toRecord(userId, it.importHash)).execute()
        saveCategorisation(userId, it.transaction.id, it.categorisation)
    }
    statements.forEach { statement ->
        val accountId = accountIds.getValue(statement.account.number)
        statement.observations.forEach { recordBalance(userId, accountId, it) }
    }
    return counts to created
}

fun Route.importStatements(db: Db) =
    route("/api/imports") {
        bodyLimit(IMPORT_BODY_LIMIT)
        post {
            call.handle {
                val userId = call.userId
                val request = call.receiveOrRaise<ImportRequest>()
                ensure(request.files.isNotEmpty()) {
                    DomainError.ValidationFailed("Choose at least one file to import")
                }
                val statements =
                    withError({ errors: List<ImportError> ->
                        DomainError.ValidationFailed(errors.joinToString("\n") { it.describe() })
                    }) {
                        Statement.parseAll(
                                Formats.all,
                                request.files.map { it.name to it.content },
                            )
                            .bind()
                    }

                val (counts, created) = db.transaction { import(userId, statements) }

                call.log.info(
                    "Imported ${counts.imported} transactions from ${statements.size} " +
                        "statements",
                    "imported" to counts.imported,
                    "skippedDuplicates" to counts.skippedDuplicates,
                    "transfers" to counts.transfers,
                    "taggedByRules" to counts.taggedByRules,
                    "accountsCreated" to created.size,
                )
                call.respond(
                    ImportResponse(
                        imported = counts.imported,
                        skippedDuplicates = counts.skippedDuplicates,
                        transfers = counts.transfers,
                        taggedByRules = counts.taggedByRules,
                        accountsCreated =
                            created.map {
                                CreatedAccountResponse(
                                    it.id,
                                    it.name.value,
                                    it.number?.value.orEmpty(),
                                )
                            },
                    )
                )
            }
        }
            .describe {
                summary = "Import bank statements"
                description =
                    "Imports CSV bank statements in one database transaction: accounts are found " +
                        "by number or created, rows already imported are skipped, transfers " +
                        "between the user's accounts are marked, rules tag the rest, and " +
                        "statement balances are recorded. A file in no known format, or any row " +
                        "that cannot be read, fails the whole request with 400, listing every " +
                        "problem. The request body may be up to 1 MB."
                tag("Imports")
                requestBody {
                    required = true
                    schema = jsonSchema<ImportRequest>()
                }
                responses {
                    json<ImportResponse>(HttpStatusCode.OK)
                    errors(
                        HttpStatusCode.BadRequest,
                        HttpStatusCode.Unauthorized,
                        HttpStatusCode.Conflict,
                        HttpStatusCode.PayloadTooLarge,
                    )
                }
            }
    }
