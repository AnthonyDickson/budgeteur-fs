package budgeteur.shared

import java.security.SecureRandom
import java.time.Instant
import java.util.UUID

/** Reads the current instant. Endpoints that depend on "now" take one. */
typealias Clock = () -> Instant

val systemClock: Clock = Instant::now

private val random = SecureRandom()

/**
 * A version 7 UUID (RFC 9562): a millisecond timestamp then random bits, so
 * ids sort by creation time like the F# server's Guid.CreateVersion7.
 */
fun uuidV7(now: Instant = Instant.now()): UUID {
    val millis = now.toEpochMilli()
    val randA = random.nextInt(1 shl 12).toLong()
    val randB = random.nextLong() and 0x3fff_ffff_ffff_ffffL
    val msb = (millis shl 16) or (0x7L shl 12) or randA
    val lsb = Long.MIN_VALUE or randB // variant 0b10
    return UUID(msb, lsb)
}
