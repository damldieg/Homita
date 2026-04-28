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
- **Calendar**: `{"id": 1, "name": "...", "color": "...", "token": "...", "upcoming_event_count": 0, "widget": 1, "created_at": "...", "updated_at": "..."}`
- **CalendarUser**: `{"id": 1, "calendar_id": 1, "user_id": 1, "role": "owner", "widget": 1, "created_at": "..."}`
- **Event**: `{"id": 1, "calendar_id": 1, "calendar_color": "...", "calendar_name": "...", "title": "...", "date_at": "Y-m-d H:i:s", "alarm": null, "created_at": "...", "updated_at": "..."}`
- **TaskList**: `{"id": 1, "name": "...", "color": "...", "token": "...", "sort": "...", "pending_task_count": 0, "widget": 1, "created_at": "...", "updated_at": "..."}`
- **TaskListUser**: `{"id": 1, "task_list_id": 1, "user_id": 1, "role": "owner", "widget": 1, "created_at": "..."}`
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
- **Output**: `Event` object.

### `PATCH /event/update`
- **Auth Required**: Yes
- **Input**:
  - `id` (int)
  - `title` (string)
  - `date_at` (string in `Y-m-d H:i:s` format)
  - `alarm` (int, optional)
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
