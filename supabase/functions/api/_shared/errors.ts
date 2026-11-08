// Errores del contrato PHP: strings exactos de ControllerAbstract/UserAuth/middlewareAuth/router.
import { json } from "./contract.ts";

export const error = (message: string, status: number): Response => json({ error: message }, status);

// Router::error de PHP: InvalidArgumentException → 400; el resto → 500 con el mensaje
export const rpcError = (body: unknown): Response => {
    const message = (body as { message?: string } | null)?.message ?? "Internal error";
    return error(message, message === "Invalid timezone" ? 400 : 500);
};

export const errAuthFieldsRequired = (): Response => error("Email and password are required", 400);
export const errInvalidCredentials = (): Response => error("Invalid credentials", 401);
export const errUnauthorized = (): Response => error("Unauthorized", 401);
export const errRouteNotFound = (): Response => error("Not Found", 404);
export const errPhpNotFound = (): Response => error("Not Found", 500);
export const errInvalidTimezone = (): Response => error("Invalid timezone", 400);
