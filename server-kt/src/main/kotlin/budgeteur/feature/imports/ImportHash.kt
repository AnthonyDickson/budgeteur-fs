package budgeteur.feature.imports

import budgeteur.domain.AccountNumber
import java.security.MessageDigest
import java.util.HexFormat

/**
 * The hash that recognises a statement row the user has already imported, so a repeated or
 * overlapping import skips it. See decision 6 in docs/csv-import.md.
 */
object ImportHash {
    /** Part of the hashed input, so a change to how it is built never matches an older hash. */
    private const val VERSION = "budgeteur-import-v1"

    /**
     * SHA-256 over the version, the statement's account number, and the row's identity fields in
     * canonical form, as lowercase hex. Each part is prefixed with its length in UTF-16 code units,
     * as the F# server's is, so no two lists of parts hash the same input. Changing this changes
     * every stored hash: re-imports would duplicate every transaction.
     */
    fun compute(accountNumber: AccountNumber, identity: List<String>): String {
        val input =
            (listOf(VERSION, accountNumber.value) + identity).joinToString("") {
                "${it.length}:$it"
            }
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return HexFormat.of().formatHex(digest)
    }
}
