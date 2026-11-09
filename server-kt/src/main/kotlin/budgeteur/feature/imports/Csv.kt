package budgeteur.feature.imports

import arrow.core.raise.Raise
import arrow.core.raise.context.raise

/** A non-blank line of a CSV file and its 1-based line number, so errors can point at it. */
data class CsvLine(val number: Int, val text: String)

/**
 * Reads the text of a bank's CSV export. Statements are UTF-8 with comma separators, and no field
 * spans lines (see Assumptions in docs/csv-import.md).
 */
object Csv {
    /** U+FEFF, which some systems write at the start of a UTF-8 file. */
    private const val BYTE_ORDER_MARK = '﻿'

    /**
     * The file's non-blank lines. A byte order mark is dropped and any line ending is accepted, so
     * exports from different systems read the same. Line numbers count the skipped blank lines.
     */
    fun lines(text: String): List<CsvLine> =
        text
            .trimStart(BYTE_ORDER_MARK)
            .replace("\r\n", "\n")
            .replace('\r', '\n')
            .split('\n')
            .mapIndexed { index, line -> CsvLine(index + 1, line) }
            .filter { it.text.isNotBlank() }

    /** Where [fields] is within a line. */
    private enum class State {
        /** At the start of a field. */
        Start,

        /** In a field without quotes. */
        Unquoted,

        /** In a quoted field. */
        Quoted,

        /** After a quote in a quoted field: a closing quote, or the first of a doubled one. */
        QuoteInQuoted,
    }

    /**
     * Splits a line into its comma-separated fields. A field in double quotes may contain commas,
     * and a doubled quote inside it stands for one quote. Fails on an unterminated quote or text
     * after a closing quote.
     */
    context(_: Raise<String>)
    fun fields(line: String): List<String> {
        val fields = mutableListOf<String>()
        val field = StringBuilder()
        var state = State.Start

        fun endField() {
            fields.add(field.toString())
            field.clear()
            state = State.Start
        }

        line.forEachIndexed { index, char ->
            when (state) {
                State.Start,
                State.Unquoted ->
                    when {
                        char == '"' && state == State.Start -> state = State.Quoted
                        char == ',' -> endField()
                        else -> {
                            field.append(char)
                            state = State.Unquoted
                        }
                    }
                State.Quoted -> if (char == '"') state = State.QuoteInQuoted else field.append(char)
                State.QuoteInQuoted ->
                    when (char) {
                        '"' -> {
                            field.append('"')
                            state = State.Quoted
                        }
                        ',' -> endField()
                        else ->
                            raise("unexpected text after a closing quote at column ${index + 1}")
                    }
            }
        }

        if (state == State.Quoted) raise("a quoted field has no closing quote")
        fields.add(field.toString())
        return fields
    }
}
