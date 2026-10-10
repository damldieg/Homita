CREATE TABLE routine (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    calendar_id INTEGER NOT NULL REFERENCES calendar(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    days TEXT NOT NULL,
    time TEXT NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT,
    active INTEGER NOT NULL DEFAULT 1,
    available_from TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE routine_user (
    routine_id INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    alarm INTEGER,
    PRIMARY KEY (routine_id, user_id)
);
ALTER TABLE event ADD COLUMN routine_id INTEGER REFERENCES routine(id) ON DELETE SET NULL;
ALTER TABLE event ADD COLUMN routine_date TEXT;
CREATE UNIQUE INDEX event_routine_date ON event(routine_id, routine_date);
CREATE TABLE routine_exception (
    routine_id INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
    routine_date TEXT NOT NULL,
    title TEXT,
    date_at TEXT,
    cancelled INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (routine_id, routine_date)
);
CREATE TABLE routine_event_alarm (
    routine_id INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
    routine_date TEXT NOT NULL,
    user_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    alarm INTEGER,
    PRIMARY KEY (routine_id, routine_date, user_id)
);
CREATE TABLE event_user_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    alarm INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(event_id, user_id)
);
INSERT INTO event_user_new SELECT * FROM event_user;
DROP TABLE event_user;
ALTER TABLE event_user_new RENAME TO event_user;
