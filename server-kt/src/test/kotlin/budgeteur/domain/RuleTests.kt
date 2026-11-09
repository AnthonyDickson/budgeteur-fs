package budgeteur.domain

import arrow.core.raise.context.either
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RuleTests {
    private fun pattern(raw: String) = either { RulePattern.create(raw) }.getOrNull()!!

    @Test
    fun `patterns are the same ignoring case, including outside ASCII`() {
        assertTrue(pattern("CAFÉ").isSameAs(pattern("café")))
        assertTrue(!pattern("CAFE").isSameAs(pattern("CAFÉ")))
    }

    @Test
    fun `a target's kind and tag id must agree`() {
        val tagId = UUID.randomUUID()
        assertEquals(RuleTarget.Tag(tagId), either { RuleTarget.create("Tag", tagId) }.getOrNull())
        assertEquals(
            RuleTarget.Transfer,
            either { RuleTarget.create("Transfer", null) }.getOrNull(),
        )
        assertTrue(either { RuleTarget.create("Tag", null) }.isLeft())
        assertTrue(either { RuleTarget.create("Transfer", tagId) }.isLeft())
        assertTrue(either { RuleTarget.create("tag", tagId) }.isLeft())
    }
}
