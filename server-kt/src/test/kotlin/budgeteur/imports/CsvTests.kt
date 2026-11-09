package budgeteur.imports

import arrow.core.Either
import arrow.core.raise.context.either
import budgeteur.feature.imports.Csv
import budgeteur.feature.imports.CsvLine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CsvTests {
    private fun fields(line: String): Either<String, List<String>> = either { Csv.fields(line) }

    @Test
    fun `lines normalise endings and skip blank lines`() {
        assertEquals(
            listOf(CsvLine(1, "a,b"), CsvLine(3, "c,d"), CsvLine(4, "e,f"), CsvLine(6, "g,h")),
            Csv.lines("﻿a,b\r\n\r\nc,d\re,f\n  \ng,h\n"),
            "a BOM and blank lines are dropped, line numbers kept",
        )
    }

    @Test
    fun `fields split on commas outside quotes`() {
        assertEquals(
            Either.Right(listOf("2026/06/17", "CITY, AUCKLAND", "", "707.00")),
            fields("2026/06/17,\"CITY, AUCKLAND\",,707.00"),
            "a quoted comma is part of the field, an empty field stays",
        )
        assertEquals(
            Either.Right(listOf("say \"hi\"", "x")),
            fields("\"say \"\"hi\"\"\",x"),
            "a doubled quote is one quote",
        )
        assertEquals(Either.Right(listOf("a", "")), fields("a,"), "a trailing comma")
        assertEquals(Either.Right(listOf("Café Māori", "ō")), fields("Café Māori,ō"), "non-ASCII")
    }

    @Test
    fun `fields reject malformed quotes`() {
        assertTrue(fields("\"unterminated,x").isLeft(), "an unterminated quote")
        assertTrue(fields("\"closed\"text,x").isLeft(), "text after a closing quote")
    }
}
