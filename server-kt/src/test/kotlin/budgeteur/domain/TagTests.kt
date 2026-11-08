package budgeteur.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TagTests {
    @Test
    fun `a name is trimmed`() {
        assertEquals("Rent", TagName.create("  Rent ").getOrNull()?.value)
    }

    @Test
    fun `a blank name is rejected`() {
        assertTrue(TagName.create(" \t").isLeft())
    }

    @Test
    fun `a name may be the maximum length but no longer`() {
        assertTrue(TagName.create("a".repeat(TagName.MAX_LENGTH)).isRight())
        assertTrue(TagName.create("a".repeat(TagName.MAX_LENGTH + 1)).isLeft())
    }
}
