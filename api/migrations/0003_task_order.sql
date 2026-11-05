CREATE TABLE task_list_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#6923E2',
    token TEXT NOT NULL UNIQUE,
    sort TEXT NOT NULL DEFAULT 'updated_at',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO task_list_new (id, name, color, token, sort, created_at, updated_at)
SELECT id, name, color, token, sort_order, created_at, updated_at FROM task_list;

DROP TABLE task_list;
ALTER TABLE task_list_new RENAME TO task_list;

ALTER TABLE task ADD COLUMN `order` INTEGER NOT NULL DEFAULT 0;

UPDATE task SET `order` = (
    SELECT rn FROM (
        SELECT t2.id, ROW_NUMBER() OVER (
            PARTITION BY t2.task_list_id
            ORDER BY
                CASE WHEN tl.sort = 'title' THEN t2.title END ASC,
                CASE WHEN tl.sort IN ('updated_at','custom') THEN t2.updated_at END DESC
        ) AS rn
        FROM task t2
        INNER JOIN task_list tl ON tl.id = t2.task_list_id
    ) ranked WHERE ranked.id = task.id
);
