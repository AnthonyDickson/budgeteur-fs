namespace Budgeteur.Shared.ApiError

type ApiError = {
    Error : string
    Details : string
    StatusCode : int option
    RequestId : string
}
