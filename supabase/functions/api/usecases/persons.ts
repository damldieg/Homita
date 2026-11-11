// person (Person*.php). Paridad A7: no creador → 500 Not Found (no 403); validación de campos
// dentro de la RPC (orden PHP: lookup-then-validate en update, PersonUpdate.php:12-13).
import { inputInt, inputString, contractInput } from "../_shared/contract.ts";
import { errPersonIdRequired, rpcPass } from "../_shared/errors.ts";
import { rpc } from "../_shared/supabase.ts";

// GET /person (PersonIndex.php): Person::VISIBLE (propio + co-miembros de calendario)
export const handlePersonIndex = async (_req: Request, token: string): Promise<Response> =>
    rpcPass(await rpc("get_persons", {}, token));

// POST /person/create (PersonCreate.php): 200 (¡no 201!); creador = caller
export const handlePersonCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    return rpcPass(await rpc("create_person", {
        p_name: inputString(input, "name"),
        p_color: inputString(input, "color"),
    }, token));
};

// PATCH /person/update (PersonUpdate.php): solo creador (findByIdAndOwner → 500 Not Found)
export const handlePersonUpdate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    if (!id) return errPersonIdRequired(); // PersonControllerAbstract.php:14
    return rpcPass(await rpc("update_person", {
        p_id: id,
        p_name: inputString(input, "name"),
        p_color: inputString(input, "color"),
    }, token));
};

// DELETE /person/delete (PersonDelete.php): solo creador
export const handlePersonDelete = async (req: Request, token: string): Promise<Response> => {
    const input = await contractInput(req);
    const id = inputInt(input, "id");
    if (!id) return errPersonIdRequired();
    return rpcPass(await rpc("delete_person", { p_id: id }, token));
};
