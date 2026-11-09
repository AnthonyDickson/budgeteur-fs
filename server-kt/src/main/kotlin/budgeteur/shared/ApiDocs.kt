package budgeteur.shared

import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.GenericElement
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.JsonSchemaInference
import io.ktor.openapi.JsonType
import io.ktor.openapi.KotlinxSerializerJsonSchemaInference
import io.ktor.openapi.OAuth2SecurityScheme
import io.ktor.openapi.OAuthFlow
import io.ktor.openapi.OAuthFlows
import io.ktor.openapi.OpenApiDoc
import io.ktor.openapi.OpenApiInfo
import io.ktor.openapi.Operation
import io.ktor.openapi.ReferenceOr
import io.ktor.openapi.Responses
import io.ktor.openapi.jsonSchema
import io.ktor.server.application.Application
import io.ktor.server.response.respondText
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.OpenApiDocSource
import io.ktor.server.routing.openapi.findSecuritySchemes
import io.ktor.server.routing.openapi.hide
import java.net.URI
import kotlin.reflect.KClass
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialInfo
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.StructureKind
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import kotlinx.serialization.serializer

const val OPENAPI_PATH = "/openapi/v1.json"

/** Matches the Scalar redirect URIs registered with the provider. */
const val SCALAR_PATH = "/scalar/v1"

/** Pinned, since the page loads it from a CDN. */
private const val SCALAR_VERSION = "1.75.1"

private val OIDC_SCOPES = listOf("openid", "profile", "email")

/** The `format` of a string field holding a calendar date, `yyyy-MM-dd`. */
const val DATE_FORMAT = "date"

/**
 * The `pattern` of a string field holding an amount. Requests may have more places, which the
 * server rounds to cents; responses always have two.
 */
const val MONEY_PATTERN = """^-?\d+(\.\d+)?$"""

/**
 * What the API docs need from outside: the OIDC client that Scalar logs in with, and the provider's
 * endpoints, read when the document is requested so the provider need not be up at startup.
 */
class ApiDocsSettings(
    val clientId: String,
    val authorizationEndpoint: () -> URI,
    val tokenEndpoint: () -> URI,
)

/**
 * Documents a string field as an enum of [type]'s constants, which must match the strings on the
 * wire. A request field stays a string, so that the request parser can report a bad value alongside
 * the other fields' failures rather than failing to decode.
 */
@OptIn(ExperimentalSerializationApi::class)
@SerialInfo
@Target(AnnotationTarget.PROPERTY)
annotation class EnumOf(val type: KClass<out Enum<*>>)

private fun ReferenceOr<JsonSchema>.map(f: (JsonSchema) -> JsonSchema): ReferenceOr<JsonSchema> =
    valueOrNull()?.let { ReferenceOr.Value(f(it)) } ?: this

/**
 * A nullable object property as `oneOf` the object and null, the shape Ktor gives a nullable
 * reference. Ktor folds the null into the object's own `type`, so the object's schema would differ
 * from its non-null uses and get a second, numbered component.
 */
private fun JsonSchema.nullableObjectAsOneOf(): JsonSchema {
    val types = (type as? JsonSchema.SchemaType.AnyOf)?.types?.toSet()
    if (title == null || types != setOf(JsonType.OBJECT, JsonType.NULL)) return this
    return JsonSchema(
        oneOf =
            listOf(
                ReferenceOr.Value(copy(type = JsonType.OBJECT)),
                ReferenceOr.Value(JsonSchema(type = JsonType.NULL)),
            )
    )
}

/**
 * Adds the [EnumOf] values to [schema] and rewrites nullable object properties, following
 * [descriptor] into list items and object properties, so a type's schema is the same wherever it
 * appears. Otherwise Ktor would see two schemas for one type and number the second.
 */
@OptIn(ExperimentalSerializationApi::class)
private fun normalised(schema: JsonSchema, descriptor: SerialDescriptor): JsonSchema =
    when (descriptor.kind) {
        StructureKind.LIST ->
            schema.copy(
                items = schema.items?.map { normalised(it, descriptor.getElementDescriptor(0)) }
            )
        StructureKind.CLASS ->
            schema.copy(
                properties =
                    schema.properties?.mapValues { (name, property) ->
                        val i = descriptor.getElementIndex(name)
                        if (i < 0) return@mapValues property
                        val values =
                            descriptor
                                .getElementAnnotations(i)
                                .filterIsInstance<EnumOf>()
                                .firstOrNull()
                                ?.type
                                ?.java
                                ?.enumConstants
                                ?.map { GenericElement(it.name) }
                        property.map { child ->
                            normalised(child, descriptor.getElementDescriptor(i))
                                .let { if (values == null) it else it.copy(enum = values) }
                                .nullableObjectAsOneOf()
                        }
                    }
            )
        else -> schema
    }

/** Ktor's schema inference from kotlinx.serialization, [normalised]. */
private val schemaInference = JsonSchemaInference { type ->
    normalised(
        KotlinxSerializerJsonSchemaInference.Default.buildSchema(type),
        serializer(type).descriptor,
    )
}

/** A response with a JSON body of type [T], described by the status's reason phrase. */
inline fun <reified T : Any> Responses.Builder.json(status: HttpStatusCode) =
    response(status.value) {
        description = status.description
        schema = jsonSchema<T>()
    }

/** Error responses, each with an [ApiError] body. */
fun Responses.Builder.errors(vararg statuses: HttpStatusCode) = statuses.forEach {
    json<ApiError>(it)
}

fun Responses.Builder.noContent() =
    response(HttpStatusCode.NoContent.value) { description = HttpStatusCode.NoContent.description }

/** A path parameter holding a UUID, which Ktor would document as a plain string. */
fun Operation.Builder.uuidPath(name: String) = parameters {
    path(name) {
        required = true
        schema = JsonSchema(type = JsonType.STRING, format = "uuid")
    }
}

/** A path parameter holding a calendar date, `yyyy-MM-dd`. */
fun Operation.Builder.datePath(name: String) = parameters {
    path(name) {
        required = true
        schema = JsonSchema(type = JsonType.STRING, format = DATE_FORMAT)
    }
}

/**
 * The bearer scheme as the OAuth 2.0 authorization code flow, so Scalar can log in and send the
 * token it gets. Ktor would infer a plain HTTP bearer scheme from the JWT provider.
 */
private fun oauthBearer(settings: ApiDocsSettings) =
    OAuth2SecurityScheme(
        flows =
            OAuthFlows(
                authorizationCode =
                    OAuthFlow(
                        authorizationUrl = settings.authorizationEndpoint().toString(),
                        tokenUrl = settings.tokenEndpoint().toString(),
                        scopes = OIDC_SCOPES.associateWith { OAuthFlow.DEFAULT_SCOPE_DESCRIPTION },
                    )
            ),
        description = "An access token from the OIDC provider. Log in through Scalar to get one.",
    )

/**
 * The OpenAPI document, built from the routing tree on each request. Ktor infers each route's
 * security requirement from the `authenticate` block around it, and the session cookie's scheme
 * from its provider.
 */
fun Application.openApiDocument(settings: ApiDocsSettings): String =
    OpenApiDocSource.Routing(
            schemaInference = schemaInference,
            securitySchemes = {
                findSecuritySchemes() + (BEARER_AUTH to ReferenceOr.Value(oauthBearer(settings)))
            },
        )
        .read(this, OpenApiDoc(info = OpenApiInfo(title = "Budgeteur API", version = appVersion)))
        .content

/** Scalar's configuration: preselect the OAuth flow with the docs' client, PKCE and scopes. */
private fun scalarConfig(clientId: String) = buildJsonObject {
    put("url", OPENAPI_PATH)
    put("theme", "deepSpace")
    putJsonObject("defaultHttpClient") {
        put("targetKey", "http")
        put("clientKey", "curl")
    }
    putJsonObject("authentication") {
        putJsonArray("preferredSecurityScheme") { add(BEARER_AUTH) }
        putJsonObject("securitySchemes") {
            putJsonObject(BEARER_AUTH) {
                putJsonObject("flows") {
                    putJsonObject("authorizationCode") {
                        put("x-scalar-client-id", clientId)
                        put("x-usePkce", "SHA-256")
                        putJsonArray("selectedScopes") { OIDC_SCOPES.forEach(::add) }
                    }
                }
            }
        }
    }
}

private fun scalarPage(clientId: String) =
    """
    <!doctype html>
    <html>
      <head>
        <title>Budgeteur API</title>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body>
        <div id="app"></div>
        <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference@$SCALAR_VERSION"></script>
        <script>
          Scalar.createApiReference('#app', ${Json.encodeToString(scalarConfig(clientId))})
        </script>
      </body>
    </html>
    """
        .trimIndent()

/** The OpenAPI document and the Scalar API reference. Development only. */
fun Route.apiDocs(settings: ApiDocsSettings) {
    get(OPENAPI_PATH) {
            call.respondText(
                call.application.openApiDocument(settings),
                ContentType.Application.Json,
            )
        }
        .hide()
    get(SCALAR_PATH) { call.respondText(scalarPage(settings.clientId), ContentType.Text.Html) }
        .hide()
}
