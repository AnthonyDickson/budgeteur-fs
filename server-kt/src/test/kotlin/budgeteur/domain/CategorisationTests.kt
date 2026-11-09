package budgeteur.domain

import arrow.core.raise.context.either
import budgeteur.shared.newId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CategorisationTests {
    private val groceries = newId()
    private val dining = newId()

    @Test
    fun `onCreate makes a tag manual and a transfer a transfer`() {
        assertEquals(
            Categorisation.Tagged(groceries, Source.Manual),
            Categorisation.onCreate(isTransfer = false, groceries),
        )
        assertEquals(
            Categorisation.Transfer(Source.Manual),
            Categorisation.onCreate(isTransfer = true, null),
        )
        assertNull(Categorisation.onCreate(isTransfer = false, null))
    }

    @Test
    fun `onUpdate keeps the source only when the tag is unchanged`() {
        val ruleTagged = Categorisation.Tagged(groceries, Source.Rule)

        assertEquals(ruleTagged, Categorisation.onUpdate(false, groceries, ruleTagged))
        assertEquals(
            Categorisation.Tagged(dining, Source.Manual),
            Categorisation.onUpdate(false, dining, ruleTagged),
        )
        assertNull(Categorisation.onUpdate(false, null, ruleTagged))
    }

    @Test
    fun `onUpdate keeps a dismissal until the user picks a tag`() {
        val dismissed = Categorisation.Dismissed

        assertEquals(dismissed, Categorisation.onUpdate(false, null, dismissed))
        assertEquals(
            Categorisation.Tagged(groceries, Source.Manual),
            Categorisation.onUpdate(false, groceries, dismissed),
        )
    }

    @Test
    fun `onUpdate marks and unmarks a transfer, keeping its source while it stays one`() {
        val detected = Categorisation.Transfer(Source.Detected)

        assertEquals(detected, Categorisation.onUpdate(true, null, detected))
        assertEquals(
            Categorisation.Transfer(Source.Manual),
            Categorisation.onUpdate(true, null, Categorisation.Tagged(groceries, Source.Rule)),
        )
        assertNull(Categorisation.onUpdate(false, null, detected))
        assertEquals(
            Categorisation.Tagged(groceries, Source.Manual),
            Categorisation.onUpdate(false, groceries, detected),
        )
    }

    @Test
    fun `a transfer cannot have a tag`() {
        assertTrue(either { Categorisation.requireNoTagOnTransfer(true, groceries) }.isLeft())
        assertTrue(either { Categorisation.requireNoTagOnTransfer(true, null) }.isRight())
        assertTrue(either { Categorisation.requireNoTagOnTransfer(false, groceries) }.isRight())
    }
}
