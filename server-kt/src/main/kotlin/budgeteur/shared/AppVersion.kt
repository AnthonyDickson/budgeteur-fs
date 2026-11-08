package budgeteur.shared

/** The running build's version, from the jar manifest; `unknown` when run from classes. */
val appVersion: String = UserPrincipal::class.java.`package`?.implementationVersion ?: "unknown"
