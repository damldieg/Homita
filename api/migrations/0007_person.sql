CREATE TABLE person (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE event_person (
    event_id INTEGER NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    person_id INTEGER NOT NULL REFERENCES person(id) ON DELETE CASCADE,
    PRIMARY KEY (event_id, person_id)
);
CREATE TABLE routine_person (
    routine_id INTEGER NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
    person_id INTEGER NOT NULL REFERENCES person(id) ON DELETE CASCADE,
    PRIMARY KEY (routine_id, person_id)
);
CREATE INDEX person_user ON person(user_id);
CREATE INDEX event_person_person ON event_person(person_id);
CREATE INDEX routine_person_person ON routine_person(person_id);
