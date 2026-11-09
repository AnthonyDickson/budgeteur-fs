package budgeteur.imports

import arrow.core.raise.context.either
import budgeteur.domain.AccountNumber
import budgeteur.feature.imports.Formats
import budgeteur.feature.imports.ImportError
import budgeteur.feature.imports.Statement

/** The anonymised bank exports in the test resources, copied from the F# server's tests. */
fun fixture(name: String): String =
    checkNotNull(object {}.javaClass.getResource("/imports/$name")) { "no fixture $name" }
        .readText()

fun parseOk(fileName: String, text: String): Statement =
    Statement.parse(Formats.all, fileName, text).fold({ errors ->
        error(
            "expected $fileName to parse, but got:\n${errors.joinToString("\n") { it.describe() }}"
        )
    }) {
        it
    }

fun parseErrors(fileName: String, text: String): List<ImportError> =
    Statement.parse(Formats.all, fileName, text).fold({ it }) {
        error("expected $fileName to fail")
    }

fun number(text: String): AccountNumber = either {
    AccountNumber.create(text)
}
    .fold({ error(it) }) { it }
