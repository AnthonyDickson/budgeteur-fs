package budgeteur.domain

import arrow.core.raise.context.either
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TagTests {
    private fun name(raw: String) = either { TagName.create(raw) }

    @Test
    fun `a name is trimmed`() {
        assertEquals("Rent", name("  Rent ").getOrNull()?.value)
    }

    @Test
    fun `a blank name is rejected`() {
        assertTrue(name(" \t").isLeft())
    }

    @Test
    fun `a name may be the maximum length but no longer`() {
        assertTrue(name("a".repeat(TagName.MAX_LENGTH)).isRight())
        assertTrue(name("a".repeat(TagName.MAX_LENGTH + 1)).isLeft())
    }
}
