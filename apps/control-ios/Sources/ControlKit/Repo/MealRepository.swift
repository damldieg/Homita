import Foundation

/// `/meal/*` (0043, menus-perfil-hogar). Todas llevan `X-Home-Id` (ver `RequestBuilder`).
public struct MealRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET meal/profile` → perfil, franjas, fichas y horario del hogar.
    public func profile() async throws -> MealProfile {
        try await client.send(APIRequest(method: .get, path: "meal/profile"), as: MealProfile.self)
    }

    /// `PATCH meal/profile` (solo con `menu.profile.edit`).
    public func updateHome(_ update: MealHomeUpdate) async throws {
        _ = try await client.send(
            APIRequest(method: .patch, path: "meal/profile", body: try client.encode(update)), as: OkResponse.self)
    }

    /// `PATCH meal/profile/member`; `eats: false` borra la ficha.
    public func updateMember(_ update: MealMemberUpdate) async throws {
        _ = try await client.send(
            APIRequest(method: .patch, path: "meal/profile/member", body: try client.encode(update)),
            as: OkResponse.self)
    }

    /// `PUT meal/schedule` body `{entries}`.
    public func setSchedule(_ entries: [MealScheduleEntry]) async throws {
        _ = try await client.send(
            APIRequest(method: .put, path: "meal/schedule", body: try client.encode(MealScheduleBody(entries: entries))),
            as: OkResponse.self)
    }

    /// `PUT meal/slots` body `{slots}`.
    public func setSlots(_ slots: [MealSlot]) async throws {
        _ = try await client.send(
            APIRequest(method: .put, path: "meal/slots", body: try client.encode(MealSlotsBody(slots: slots))),
            as: OkResponse.self)
    }

    // MARK: Menú semanal (0044)

    /// `GET meal/plan?week_start=`: nil si la semana no tiene plan.
    public func plan(weekStart: String) async throws -> MealPlan? {
        try await client.send(
            APIRequest(method: .get, path: "meal/plan", query: [URLQueryItem(name: "week_start", value: weekStart)]),
            as: MealPlan?.self)
    }

    /// `PATCH meal/plan/items`: crea el plan en borrador si no existe (`expectedRevision` 0) y
    /// devuelve el plan completo. 409 `Stale meal plan revision` si la revisión ya no es la vigente.
    public func saveItems(weekStart: String, expectedRevision: Int, items: [MealPlanItem],
                          deleteIds: [Int64] = []) async throws -> MealPlan {
        let body = MealPlanItemsBody(weekStart: weekStart, expectedRevision: expectedRevision, items: items, deleteIds: deleteIds)
        return try await client.send(
            APIRequest(method: .patch, path: "meal/plan/items", body: try client.encode(body)), as: MealPlan.self)
    }

    /// `POST meal/plan/accept`
    public func accept(planId: Int64, expectedRevision: Int) async throws -> MealPlan {
        try await client.send(
            APIRequest(method: .post, path: "meal/plan/accept",
                       body: try client.encode(MealPlanAcceptBody(planId: planId, expectedRevision: expectedRevision))),
            as: MealPlan.self)
    }

    /// `POST meal/plan/archive`: libera la semana. Con `expectedRevision`, 409 si el plan cambió.
    public func archive(planId: Int64, expectedRevision: Int? = nil) async throws -> MealPlan {
        try await client.send(
            APIRequest(method: .post, path: "meal/plan/archive", body: try client.encode(MealPlanArchiveBody(planId: planId, expectedRevision: expectedRevision))),
            as: MealPlan.self)
    }

    /// `POST meal/plan/copy` (201): 409 `Meal plan exists` si la semana destino ya tiene plan.
    public func copyWeek(from: String, to: String) async throws -> MealPlan {
        try await client.send(
            APIRequest(method: .post, path: "meal/plan/copy",
                       body: try client.encode(MealPlanCopyBody(fromWeek: from, toWeek: to))),
            as: MealPlan.self)
    }

    /// `GET meal/plan/check?plan_id=`
    public func check(planId: Int64) async throws -> [MealIssue] {
        try await client.send(
            APIRequest(method: .get, path: "meal/plan/check", query: [URLQueryItem(name: "plan_id", value: String(planId))]),
            as: [MealIssue].self)
    }

    /// `GET meal/today?date=`: sin fecha, hoy en la zona del hogar.
    public func today(date: String? = nil) async throws -> MealsToday {
        let query = date.map { [URLQueryItem(name: "date", value: $0)] } ?? []
        return try await client.send(APIRequest(method: .get, path: "meal/today", query: query), as: MealsToday.self)
    }
}
