package budgeteur.feature.transaction

import budgeteur.shared.Db
import io.ktor.server.routing.Route

/** The slice's routes. Shared by the server and the test host so both route the same handlers. */
fun Route.transactionEndpoints(db: Db) {
    createTransaction(db)
    searchTransactions(db)
    readTransaction(db)
    updateTransaction(db)
    deleteTransaction(db)
}

/**
 * Development only: the page reads through search. See decision 7 in docs/transaction-search.md.
 */
fun Route.transactionDevelopmentEndpoints(db: Db) {
    readAllTransactions(db)
}
