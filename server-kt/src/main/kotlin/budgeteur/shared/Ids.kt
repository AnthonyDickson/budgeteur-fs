package budgeteur.shared

import java.time.Instant
import java.util.UUID
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid
import kotlin.uuid.toJavaUuid

/** Reads the current instant. Endpoints that depend on "now" take one. */
typealias Clock = () -> Instant

val systemClock: Clock = Instant::now

/**
 * A version 7 UUID: ids sort by creation time, which keeps index inserts in order. The generator is
 * still experimental in Kotlin 2.4; the rest of the Uuid API is stable.
 */
@OptIn(ExperimentalUuidApi::class) fun newId(): UUID = Uuid.generateV7().toJavaUuid()
