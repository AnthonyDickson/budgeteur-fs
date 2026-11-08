package budgeteur.shared

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.security.SecureRandom
import java.util.Base64

/**
 * The keys that encrypt (AES-128) and sign (HMAC-SHA256) the auth cookies. Changing them signs
 * every user out.
 */
class SessionKeys(val encryption: ByteArray, val signing: ByteArray) {
    init {
        require(encryption.size == ENCRYPTION_BYTES && signing.size == SIGNING_BYTES)
    }

    companion object {
        private const val ENCRYPTION_BYTES = 16
        private const val SIGNING_BYTES = 32

        fun random(): SessionKeys {
            val bytes = ByteArray(ENCRYPTION_BYTES + SIGNING_BYTES).also(SecureRandom()::nextBytes)
            return fromBytes(bytes)
        }

        /**
         * Reads the keys from [file], creating it with new keys, readable by the owner only, if it
         * does not exist. A container keeps the file on a volume so sessions survive a restart.
         */
        fun loadOrCreate(file: Path): SessionKeys {
            if (Files.notExists(file)) {
                val keys = random()
                file.toAbsolutePath().parent?.let(Files::createDirectories)
                Files.createFile(file)
                runCatching {
                    Files.setPosixFilePermissions(
                        file,
                        PosixFilePermissions.fromString("rw-------"),
                    )
                }
                Files.writeString(
                    file,
                    Base64.getEncoder().encodeToString(keys.encryption + keys.signing),
                )
                return keys
            }
            val bytes = Base64.getDecoder().decode(Files.readString(file).trim())
            require(bytes.size == ENCRYPTION_BYTES + SIGNING_BYTES) {
                "$file does not hold session keys"
            }
            return fromBytes(bytes)
        }

        private fun fromBytes(bytes: ByteArray) =
            SessionKeys(
                bytes.copyOfRange(0, ENCRYPTION_BYTES),
                bytes.copyOfRange(ENCRYPTION_BYTES, bytes.size),
            )
    }
}
