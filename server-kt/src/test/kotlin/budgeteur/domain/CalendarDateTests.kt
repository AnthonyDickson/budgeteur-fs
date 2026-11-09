package budgeteur.domain

import arrow.core.raise.context.either
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CalendarDateTests {
    private fun parse(raw: String) = either { parseCalendarDate(raw) }

    @Test
    fun `a date round-trips through yyyy-MM-dd`() {
        val date = parse("2026-03-08").getOrNull()
        assertEquals(LocalDate.of(2026, 3, 8), date)
        assertEquals("2026-03-08", date?.formatCalendarDate())
    }

    @Test
    fun `only yyyy-MM-dd dates that exist parse`() {
        listOf("2026-02-30", "2026-3-8", "08/03/2026", "+10000-01-01", "2026-03-08T00:00", "")
            .forEach { assertTrue(parse(it).isLeft(), "\"$it\" should not parse") }
    }

    @Test
    fun `a leap day parses only in a leap year`() {
        assertTrue(parse("2028-02-29").isRight())
        assertTrue(parse("2026-02-29").isLeft())
    }
}
