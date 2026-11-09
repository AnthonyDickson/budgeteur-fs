@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.transaction

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.either
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.raise
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import budgeteur.domain.Frequency
import budgeteur.domain.Money
import budgeteur.domain.ReportingPeriod
import budgeteur.domain.RulePattern
import budgeteur.domain.formatCalendarDate
import budgeteur.domain.parseCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import budgeteur.shared.MONEY_PATTERN
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID
import kotlin.uuid.Uuid
import kotlin.uuid.toJavaUuid
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

// Validates search requests, resolves date presets, and pages matches. See
// docs/transaction-search.md.

/** The most matches a page holds. */
const val PAGE_SIZE = 100

/** A named range resolved from the client's today, or custom days. See decision 3. */
enum class DatePreset {
    AnyTime,
    ThisMonth,
    LastMonth,
    ThisYear,
    LastYear,

    /** The financial year from 1 April containing today. */
    ThisFinancialYear,
    LastFinancialYear,
    Custom,
}

/** The account criterion's states, as the request names them. */
enum class AccountState {
    Any,
    NoAccount,
    Account,
}

/** Which account a match has. See decision 4. */
sealed interface AccountCriterion {
    data object Any : AccountCriterion

    data object NoAccount : AccountCriterion

    data class Account(val id: UUID) : AccountCriterion
}

/** The tag criterion's states, as the request names them. */
enum class TagState {
    Any,
    WithoutTag,
    Untagged,
    Dismissed,
    Transfer,
    Tag,
}

/** How a match is categorised. See decision 4. */
sealed interface TagCriterion {
    data object Any : TagCriterion

    /** Untagged or dismissed. */
    data object WithoutTag : TagCriterion

    data object Untagged : TagCriterion

    data object Dismissed : TagCriterion

    data object Transfer : TagCriterion

    data class Tag(val id: UUID) : TagCriterion
}

/** A credit is positive and a debit negative, so a zero amount matches only [Any]. */
enum class Direction {
    Any,
    Credit,
    Debit,
}

/** A valid search, with a date preset resolved to its days. A match meets every criterion. */
data class Search(
    val text: RulePattern? = null,
    /** The first day, inclusive. */
    val from: LocalDate? = null,
    /** The last day, inclusive. */
    val to: LocalDate? = null,
    val account: AccountCriterion = AccountCriterion.Any,
    val tag: TagCriterion = TagCriterion.Any,
    val direction: Direction = Direction.Any,
    /** The smallest absolute amount, inclusive. */
    val minimum: Money? = null,
    /** The largest absolute amount, inclusive. */
    val maximum: Money? = null,
)

/** Where the next page starts: after this match, newest first. See decision 6. */
data class Cursor(val date: LocalDate, val id: UUID) {
    /** Opaque to the client. */
    fun format() = "${date.formatCalendarDate()}_$id"

    companion object {
        context(_: Raise<String>)
        fun parse(raw: String): Cursor {
            val parts = raw.split('_')
            val date = parts.getOrNull(0)?.let { either { parseCalendarDate(it) }.getOrNull() }
            val id = parts.getOrNull(1)?.let(Uuid::parseHexDashOrNull)?.toJavaUuid()
            ensure(parts.size == 2 && date != null && id != null) { "The cursor is malformed" }
            return Cursor(date, id)
        }
    }
}

@Serializable
@JsonSchema.Description("The dates criterion.")
data class SearchDatesRequest(
    @EnumOf(DatePreset::class) val preset: String,
    @JsonSchema.Description("The first day, inclusive. Custom dates only.")
    @JsonSchema.Format(DATE_FORMAT)
    val from: String? = null,
    @JsonSchema.Description("The last day, inclusive. Custom dates only.")
    @JsonSchema.Format(DATE_FORMAT)
    val to: String? = null,
)

@Serializable
@JsonSchema.Description("The account criterion.")
data class SearchAccountRequest(
    @EnumOf(AccountState::class) val state: String,
    @JsonSchema.Description("The account's id, for the state Account only.")
    @JsonSchema.Format("uuid")
    val id: UUID? = null,
)

@Serializable
@JsonSchema.Description("The tag criterion.")
data class SearchTagRequest(
    @JsonSchema.Description("WithoutTag is untagged or dismissed.")
    @EnumOf(TagState::class)
    val state: String,
    @JsonSchema.Description("The tag's id, for the state Tag only.")
    @JsonSchema.Format("uuid")
    val id: UUID? = null,
)

@Serializable
@JsonSchema.Description("The amount criterion: a direction and a range of sizes.")
data class SearchAmountRequest(
    @JsonSchema.Description("Credit is a positive amount and Debit a negative one.")
    @EnumOf(Direction::class)
    val direction: String,
    @JsonSchema.Description("The smallest absolute amount, inclusive.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val minimum: String? = null,
    @JsonSchema.Description("The largest absolute amount, inclusive.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val maximum: String? = null,
)

@Serializable
@JsonSchema.Description("The criteria of a search, combined with AND.")
data class SearchCriteriaRequest(
    @JsonSchema.Description(
        "Text the description contains, ignoring case. Trimmed and validated like a rule " +
            "pattern; blank text sets no criterion."
    )
    val text: String,
    val dates: SearchDatesRequest,
    val account: SearchAccountRequest,
    val tag: SearchTagRequest,
    val amount: SearchAmountRequest,
)

/** Fields that hold dates, amounts and enum names stay strings, so every failure is reported. */
@Serializable
@JsonSchema.Description("Payload for searching transactions.")
data class SearchRequest(
    val criteria: SearchCriteriaRequest,
    @JsonSchema.Description("The client's date, which date presets are resolved from.")
    @JsonSchema.Format(DATE_FORMAT)
    val today: String,
    @JsonSchema.Description("The previous page's cursor, or none for the first page.")
    val cursor: String? = null,
)

/**
 * The first and last days of a preset other than custom, from the client's [today]. "Last" is the
 * period before the one containing today.
 */
fun DatePreset.resolve(today: LocalDate): Pair<LocalDate?, LocalDate?> {
    fun days(frequency: Frequency, last: Boolean): Pair<LocalDate, LocalDate> {
        val current = ReportingPeriod.containing(frequency, today)
        val period = if (last) current.previous() else current
        return period.from to period.to
    }

    return when (this) {
        DatePreset.AnyTime,
        DatePreset.Custom -> null to null
        DatePreset.ThisMonth -> days(Frequency.Monthly, last = false)
        DatePreset.LastMonth -> days(Frequency.Monthly, last = true)
        DatePreset.ThisYear -> days(Frequency.CalendarYear, last = false)
        DatePreset.LastYear -> days(Frequency.CalendarYear, last = true)
        DatePreset.ThisFinancialYear -> days(Frequency.FinancialYear, last = false)
        DatePreset.LastFinancialYear -> days(Frequency.FinancialYear, last = true)
    }
}

/** One of [E]'s constants by name, or a failure naming [what] and listing them. */
context(_: Raise<String>)
private inline fun <reified E : Enum<E>> parseName(what: String, raw: String): E =
    ensureNotNull(enumValues<E>().find { it.name == raw }) {
        val expected = enumValues<E>().joinToString(", ") { "\"${it.name}\"" }
        "\"$raw\" is not a valid $what, expecting one of $expected."
    }

context(_: Raise<String>)
private fun text(raw: String): RulePattern? = if (raw.isBlank()) null else RulePattern.create(raw)

context(_: Raise<String>)
private fun SearchDatesRequest.days(today: String): Pair<LocalDate?, LocalDate?> {
    val today = parseCalendarDate(today)
    val preset = parseName<DatePreset>("date preset", preset)
    val from = from?.let { parseCalendarDate(it) }
    val to = to?.let { parseCalendarDate(it) }
    return when {
        preset == DatePreset.Custom -> {
            ensure(from == null || to == null || from <= to) {
                "The first day must be on or before the last day"
            }
            from to to
        }
        from == null && to == null -> preset.resolve(today)
        else -> raise("Only custom dates take a first or last day")
    }
}

/** The states that take no id map to [withoutId]; [idState] needs an id. */
context(_: Raise<String>)
private fun <S, C> criterion(
    name: String,
    state: S,
    id: UUID?,
    idState: S,
    withId: (UUID) -> C,
    withoutId: (S) -> C,
): C =
    if (state == idState) {
        withId(ensureNotNull(id) { "The $name state $state needs an id" })
    } else {
        ensure(id == null) { "The $name state $state takes no id" }
        withoutId(state)
    }

context(_: Raise<String>)
private fun SearchAccountRequest.criterion(): AccountCriterion =
    criterion(
        "account",
        parseName<AccountState>("account state", state),
        id,
        AccountState.Account,
        AccountCriterion::Account,
    ) {
        when (it) {
            AccountState.NoAccount -> AccountCriterion.NoAccount
            else -> AccountCriterion.Any
        }
    }

context(_: Raise<String>)
private fun SearchTagRequest.criterion(): TagCriterion =
    criterion("tag", parseName<TagState>("tag state", state), id, TagState.Tag, TagCriterion::Tag) {
        when (it) {
            TagState.WithoutTag -> TagCriterion.WithoutTag
            TagState.Untagged -> TagCriterion.Untagged
            TagState.Dismissed -> TagCriterion.Dismissed
            TagState.Transfer -> TagCriterion.Transfer
            else -> TagCriterion.Any
        }
    }

/** A size is money: non-negative, with at most two decimal places. */
context(_: Raise<String>)
private fun size(name: String, raw: String): Money {
    val size = Money.parse(raw)
    ensure(size >= Money.ZERO) { "The $name cannot be negative" }
    // Parsing rounds, so a size with more places reads differently once parsed.
    ensure(size.toBigDecimal().compareTo(BigDecimal(raw)) == 0) {
        "The $name can have at most two decimal places"
    }
    return size
}

context(_: Raise<String>)
private fun SearchAmountRequest.sizes(): Pair<Money?, Money?> {
    val minimum = minimum?.let { size("minimum", it) }
    val maximum = maximum?.let { size("maximum", it) }
    ensure(minimum == null || maximum == null || minimum <= maximum) {
        "The minimum cannot be more than the maximum"
    }
    return minimum to maximum
}

/** Validates a request, reporting every failure in one error, one per line. */
context(_: Raise<DomainError>)
fun SearchRequest.validate(): Pair<Search, Cursor?> =
    withError({ errors: NonEmptyList<String> ->
        DomainError.ValidationFailed(errors.joinToString("\n"))
    }) {
        zipOrAccumulate(
            { text(criteria.text) },
            { criteria.dates.days(today) },
            { criteria.account.criterion() },
            { criteria.tag.criterion() },
            { parseName<Direction>("direction", criteria.amount.direction) },
            { criteria.amount.sizes() },
            { cursor?.let { Cursor.parse(it) } },
        ) { text, (from, to), account, tag, direction, (minimum, maximum), cursor ->
            Search(text, from, to, account, tag, direction, minimum, maximum) to cursor
        }
    }

/**
 * Splits the matches read for a page, up to one more than [PAGE_SIZE], into the page and the cursor
 * for the next page, or null on the last page.
 */
fun <T> page(matches: List<T>, cursorOf: (T) -> Cursor): Pair<List<T>, Cursor?> {
    val page = matches.take(PAGE_SIZE)
    return page to if (matches.size > PAGE_SIZE) cursorOf(page.last()) else null
}
