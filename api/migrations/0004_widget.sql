ALTER TABLE calendar_user ADD COLUMN widget INTEGER NOT NULL DEFAULT 1;

UPDATE calendar_user SET widget = true;

ALTER TABLE task_list_user ADD COLUMN widget INTEGER NOT NULL DEFAULT 1;

UPDATE task_list_user SET widget = true;
