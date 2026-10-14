# API Endpoints Documentation

This document describes all the available API endpoints in the backend, including their expected inputs and outputs.

## General Information

- **Base Format**: All endpoints consume and produce JSON (`Content-Type: application/json`). Data can be passed as a JSON body or via URL query parameters.
- **Authentication**: Endpoints requiring authentication expect an `Authorization: Bearer <token>` header.
- **Errors**: In case of failure, endpoints return a non-200 HTTP status code with a JSON payload in the format `{"error": "Error message description"}`.

---

## Models

When an endpoint returns an object or a list of objects, they map to the following public property structures:

- **User**: `{"id": 1, "name": "...", "email": "...", "token": "..." (only on auth/create), "created_at": "...", "updated_at": "..."}` *(Note: `password` is never exposed).*
- **Calendar**: `{"id": 1, "name": "...", "color": "...", "token": "...", "upcoming_event_count": 0, "widget": 1, "dashboard": 1, "created_at": "...", "updated_at": "..."}`
- **CalendarUser**: `{"id": 1, "calendar_id": 1, "user_id": 1, "role": "owner", "widget": 1, "dashboard": 1, "created_at": "..."}`
- **Event**: `{"id": 1, "calendar_id": 1, "calendar_color": "...", "calendar_name": "...", "title": "...", "date_at": "Y-m-d H:i:s", "routine_id": null, "routine_date": null, "alarm": null, "persons": [{"id": 1, "user_id": 1, "name": "...", "color": "#RRGGBB"}], "created_at": "...", "updated_at": "..."}`
- **Person**: `{"id": 1, "user_id": 1, "name": "...", "color": "#RRGGBB", "created_at": "...", "updated_at": "..."}`
- **TaskList**: `{"id": 1, "name": "...", "color": "...", "token": "...", "sort": "...", "pending_task_count": 0, "widget": 1, "dashboard": 1, "created_at": "...", "updated_at": "..."}`
- **TaskListUser**: `{"id": 1, "task_list_id": 1, "user_id": 1, "role": "owner", "widget": 1, "dashboard": 1, "created_at": "..."}`
- **Task**: `{"id": 1, "task_list_id": 1, "task_list_color": "...", "task_list_name": "...", "title": "...", "order": 1, "completed_at": null, "created_at": "...", "updated_at": "..."}`

---

## 1. Config

### `GET /config`
- **Auth Required**: No
- **Input**: None
- **Output**: JSON object with public configuration variables.

---

## 2. User & Auth

### `POST /user/create`
- **Auth Required**: No
- **Input**:
  - `name` (string)
  - `email` (string)
  - `password` (string)
- **Output**: `User` object (includes authentication `token`).

### `POST /user/auth`
- **Auth Required**: No
- **Input**:
  - `email` (string)
  - `password` (string)
- **Output**: `User` object (includes authentication `token`).

### `PATCH /user/update`
- **Auth Required**: Yes
- **Input**:
  - `name` (string, optional)
  - `email` (string, optional)
  - `password` (string, optional)
- **Output**: `User` object.

---

## 3. Calendars

### `GET /calendar`
- **Auth Required**: Yes
- **Input**: None
- **Output**: Array of `Calendar` objects belonging to the user.

### `GET /calendar/detail`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `Calendar` object.

### `POST /calendar/create`
- **Auth Required**: Yes
- **Input**:
  - `name` (string)
  - `color` (string)
  - `widget` (boolean, optional)
- **Output**: `Calendar` object.

### `PATCH /calendar/update`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
  - `name` (string)
  - `color` (string)
  - `widget` (boolean, optional)
- **Output**: `Calendar` object.

### `DELETE /calendar/delete`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `{"success": true}`

---

## 4. Calendar Users

### `GET /calendar/user`
- **Auth Required**: Yes
- **Input**:
  - `calendar_id` (int)
- **Output**: Array of `CalendarUser` objects.

### `POST /calendar/user`
- **Auth Required**: Yes
- **Input**:
  - `calendar_id` (int)
  - `email` (string)
- **Output**: `CalendarUser` object of the invited user.

### `DELETE /calendar/user`
- **Auth Required**: Yes
- **Input**:
  - `calendar_id` (int)
  - `user_id` (int)
- **Output**: `{"status": "ok"}`

---

## 5. Events

### `GET /event`
- **Auth Required**: Yes
- **Input** (Filters):
  - `calendar_id` (int, optional)
  - `search` (string, optional)
  - `start_date` (timestamp/string, optional)
  - `end_date` (timestamp/string, optional)
  - `limit` (int, optional)
  - `offset` (int, optional)
  - `order_mode` (string, optional: `ASC` or `DESC`)
  - `widget` (boolean, optional)
  - `dashboard` (boolean, optional: only events from calendars the user shows on the dashboard)
  - `routine` (boolean, optional: `false` returns only regular events, `true` only routine sessions; omitted returns both)
  - `person_id` (int, optional: events assigned to that person, including routine sessions through their routine)
- **Output**: Array of `Event` objects.

### `GET /event/detail`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `Event` object.

### `POST /event/create`
- **Auth Required**: Yes
- **Input**:
  - `calendar_id` (int)
  - `title` (string)
  - `date_at` (string in `Y-m-d H:i:s` format)
  - `alarm` (int, optional)
  - `person_ids` (int[], optional: replaces the assigned persons; omitted keeps them)
- **Output**: `Event` object.

### `PATCH /event/update`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
  - `title` (string)
  - `date_at` (string in `Y-m-d H:i:s` format)
  - `alarm` (int, optional)
  - `person_ids` (int[], optional: replaces the assigned persons; omitted keeps them)
- **Output**: `Event` object.

### `PATCH /event/alarm`
- **Auth Required**: Yes
- **Input**:
  - `event_id` (int)
  - `alarm` (int)
- **Output**: `Event` object.

### `DELETE /event/delete`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `{"success": true}`

---

## 6. Task Lists

### `GET /task-list`
- **Auth Required**: Yes
- **Input**: None
- **Output**: Array of `TaskList` objects.

### `GET /task-list/detail`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `TaskList` object.

### `POST /task-list/create`
- **Auth Required**: Yes
- **Input**:
  - `name` (string)
  - `color` (string)
  - `sort` (string)
  - `widget` (boolean, optional)
- **Output**: `TaskList` object.

### `PATCH /task-list/update`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
  - `name` (string)
  - `color` (string)
  - `sort` (string)
  - `widget` (boolean, optional)
- **Output**: `TaskList` object.

### `DELETE /task-list/delete`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `{"success": true}`

---

## 7. Task List Users

### `GET /task-list/user`
- **Auth Required**: Yes
- **Input**:
  - `task_list_id` (int)
- **Output**: Array of `TaskListUser` objects.

### `POST /task-list/user`
- **Auth Required**: Yes
- **Input**:
  - `task_list_id` (int)
  - `email` (string)
- **Output**: `TaskListUser` object of the invited user.

### `DELETE /task-list/user`
- **Auth Required**: Yes
- **Input**:
  - `task_list_id` (int)
  - `user_id` (int)
- **Output**: `{"status": "ok"}`

---

## 8. Tasks

### `GET /task`
- **Auth Required**: Yes
- **Input** (Filters):
  - `task_list_id` (int, optional)
  - `widget` (boolean, optional)
  - `dashboard` (boolean, optional: only tasks from lists the user shows on the dashboard)
- **Output**: Array of `Task` objects.

### `GET /task/detail`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `Task` object.

### `POST /task/create`
- **Auth Required**: Yes
- **Input**:
  - `task_list_id` (int)
  - `title` (string)
- **Output**: `Task` object.

### `PATCH /task/update`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
  - `title` (string)
- **Output**: `Task` object.

### `PATCH /task/complete`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
  - `completed` (boolean)
- **Output**: `Task` object.

### `PATCH /task/order`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
  - `position` (int)
- **Output**: `Task` object.

### `DELETE /task/delete`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
- **Output**: `{"success": true}`

---

## Routines

Deploy migration `0006_routine.sql` before deploying this API or the Android routines feature. Routine and event requests accept an optional IANA `timezone` query parameter (for example `Europe/Madrid`), defaulting to `UTC`. Event dates and routine times remain floating local values: the timezone determines the current local cutoff; it does not convert or fix the recurrence to that zone.

All endpoints require authentication and calendar membership. Owners and other related members can create, edit, pause and delete routines. Alarms belong only to the requesting user.

**Routine response:**

```json
{"id":1,"calendar_id":1,"calendar_name":"Training","calendar_color":"#6923E2","title":"Workout","days":[1,3,5],"time":"18:30","start_date":"2026-10-10","end_date":null,"active":true,"alarm":15}
```

Additional creation/update timestamps may be returned. `days` uses ISO weekdays (Monday 1 through Sunday 7). Dates use `YYYY-MM-DD` and are inclusive; the optional end date must not precede the start. Time uses `HH:mm`, with one shared hour for all selected days. `active` is boolean. `alarm` is nonnegative minutes or `null` for no reminder.

| Endpoint | Input | Output |
| --- | --- | --- |
| `GET /routine` | Optional `timezone` | Array of accessible routines |
| `GET /routine/detail` | `id`, optional `timezone` | Routine |
| `POST /routine/create` | `calendar_id`, `title`, `days`, `time`, `start_date`, `end_date` (optional), `active`, `alarm` (optional), `person_ids` (optional) | Routine |
| `PATCH /routine/update` | `id`, `title`, `days`, `time`, `start_date`, `end_date` (optional), `active`, `person_ids` (optional) | Routine |
| `PATCH /routine/alarm` | `id`, `alarm` | Routine with requesting user's alarm |
| `DELETE /routine/delete` | `id` | `{"success":true}` |

The calendar cannot be changed after creation. Routine edits do not change anyone's personal alarm. Use `/routine/alarm` separately when editing your reminder.

Active routines materialize real events for today and the following 89 days on routine/event reads and routine creation/update. Repeated and concurrent reads retain event IDs and do not duplicate sessions. Past sessions are never generated retroactively or rewritten by routine edits. Future individual edits and cancellations override the series, including after pausing and reactivating. An edited session can remain outside the normal generation window.

Pausing removes future sessions, retaining history and exceptions. Reactivation starts from the current local time. Deleting removes future sessions and detaches past sessions while retaining their personal alarm snapshots.

Event responses now include `routine_id` and `routine_date` (nullable); `routine_date` is the original occurrence date, even when an individual event is moved. Existing `/event/update` and `/event/delete` modify/cancel only that session. `/event/alarm` with `alarm:null` explicitly mutes a routine session, overriding the routine reminder; other users' reminders are unchanged. Clients must reconcile the complete list of future events after routine edits and cancel local alarms for removed event IDs.

Run the isolated behavioral check with `php tests/routines.php`. It uses a temporary SQLite database and never migrates or writes the deployed database. When `pcntl` is available it also checks generation through concurrent SQLite connections.

## Persons

Deploy migration `0007_person.sql` first. Persons (family members, for example) can be assigned to events and routines. A person belongs to the user who created it and is visible to that user and to every user who shares at least one calendar with them. Anyone who sees a person can assign it; only its creator can edit or delete it.

| Endpoint | Input | Output |
| --- | --- | --- |
| `GET /person` | — | Array of visible `Person` objects, ordered by name, each with `editable` (true when the requesting user created it) |
| `POST /person/create` | `name` (1–50 characters), `color` (`#RRGGBB`) | `Person` with `editable` |
| `PATCH /person/update` | `id`, `name`, `color` | `Person` with `editable` |
| `DELETE /person/delete` | `id` | `{"success":true}` |

Events and routines return `persons` (`[{"id","user_id","name","color"}]`, empty when none). Create and update accept `person_ids`: an array replaces the current assignment, `[]` clears it and omitting it keeps it. Unknown or non-visible IDs fail with `Invalid person` and nothing is saved. Routine sessions always show the persons of their routine, so changes to the routine apply immediately; deleting a routine copies them onto the detached past sessions. Deleting a person removes its assignments.

Run the isolated behavioral check with `php tests/persons.php`.

## Dashboard

Deploy migration `0008_dashboard.sql` first. Each user chooses which of their calendars and task lists the wall dashboard shows (`calendar_user.dashboard` / `task_list_user.dashboard`, all shown by default). The choice is per user, so sharing a calendar does not change what other users show.

| Endpoint | Input | Output |
| --- | --- | --- |
| `GET /dashboard` | — | `{"calendars":[{"id","name","color","dashboard"}],"task_lists":[{"id","name","color","dashboard"}]}` with `dashboard` as boolean |
| `POST /dashboard/update` | `calendar_ids` (int[], optional), `task_list_ids` (int[], optional) | Same as `GET /dashboard` |

`POST /dashboard/update` sets exactly the given IDs to shown and the rest of the user's calendars (or lists) to hidden; `[]` hides all and omitting a key keeps it. IDs the user does not belong to fail with `Invalid calendar` / `Invalid task list` and nothing is saved. The dashboard reads its content with `GET /event?dashboard=true` and `GET /task?dashboard=true`.

Run the isolated behavioral check with `php tests/dashboard.php`.
