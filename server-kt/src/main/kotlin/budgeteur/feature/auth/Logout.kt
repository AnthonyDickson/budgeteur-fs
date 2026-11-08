package budgeteur.feature.auth

import budgeteur.shared.LoginConfig
import budgeteur.shared.UserSession
import io.ktor.server.response.respondRedirect
import io.ktor.server.routing.Route
import io.ktor.server.routing.post
import io.ktor.server.sessions.clear
import io.ktor.server.sessions.sessions

const val LOGOUT_PATH = "/logout"

/**
 * The client page shown after logging out. It makes no API request, so it does not send the user
 * straight back to the provider.
 */
const val SIGNED_OUT_PATH = "/signed-out"

/**
 * Clears the session cookie, then ends the provider's session through its logout page. Without one
 * the provider session outlives the app's, so the user lands on the client's signed out page rather
 * than being logged straight back in.
 *
 * POST, so another site cannot log the user out with a link: the SameSite=Lax cookie is not sent
 * with its cross-site form posts.
 */
fun Route.logout(login: LoginConfig) =
    post(LOGOUT_PATH) {
        // Authelia 4.39 does not support RP-Initiated Logout
        // (https://github.com/authelia/authelia/pull/11660), hence the configured logout page.
        call.sessions.clear<UserSession>()
        call.respondRedirect(login.logoutUrl ?: SIGNED_OUT_PATH)
    }
