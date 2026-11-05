<?php declare(strict_types=1);

namespace App\Models;

use InvalidArgumentException;

/**
 * Personas asignables a eventos y rutinas. Las crea un usuario y las ve (y asigna)
 * cualquiera que comparta algún calendario con él; solo el creador puede editarlas.
 */
class Person extends ModelAbstract
{
    public int $id;
    public int $user_id;
    public string $name;
    public string $color;
    public string $created_at;
    public string $updated_at;

    private const VISIBLE = 'SELECT p.* FROM person p WHERE (p.user_id=:user_id OR p.user_id IN (SELECT o.user_id FROM calendar_user m INNER JOIN calendar_user o ON o.calendar_id=m.calendar_id WHERE m.user_id=:user_id))';

    public static function validate(array $data): array
    {
        $name = is_string($data['name'] ?? null) ? trim($data['name']) : '';
        $color = $data['color'] ?? null;
        if ($name === '' || mb_strlen($name) > 50) throw new InvalidArgumentException('Name is required (max 50 characters)');
        if (!is_string($color) || !preg_match('/^#[0-9A-Fa-f]{6}$/', $color)) throw new InvalidArgumentException('Color must be #RRGGBB');
        return ['name' => $name, 'color' => strtoupper($color)];
    }

    public static function create(int $userId, array $data): self
    {
        $id = self::database()->insert('INSERT INTO person (user_id,name,color) VALUES (:user_id,:name,:color)', self::validate($data) + ['user_id' => $userId]);
        return self::findByIdAndOwner($id, $userId);
    }

    public static function findVisibleForUser(int $userId): array
    {
        return array_map(static fn(array $row) => new self($row), self::database()->select(self::VISIBLE.' ORDER BY p.name COLLATE NOCASE, p.id', ['user_id' => $userId]));
    }

    public static function findByIdAndOwner(int $id, int $userId): self
    {
        return new self(self::database()->selectOneOrFail('SELECT * FROM person WHERE id=:id AND user_id=:user_id', ['id' => $id, 'user_id' => $userId]));
    }

    public function update(array $data): void
    {
        self::database()->execute('UPDATE person SET name=:name,color=:color,updated_at=CURRENT_TIMESTAMP WHERE id=:id', self::validate($data) + ['id' => $this->id]);
    }

    public function delete(): void
    {
        self::database()->execute('DELETE FROM person WHERE id=:id', ['id' => $this->id]);
    }

    /** Valida `person_ids`: null si no se envía (no se toca la asignación), o la lista de ids visibles para el usuario. */
    public static function validateIds(mixed $ids, int $userId): ?array
    {
        if ($ids === null) return null;
        if (!is_array($ids) || !array_is_list($ids)) throw new InvalidArgumentException('person_ids must be a list');
        foreach ($ids as $id) {
            if (!is_int($id) || $id < 1) throw new InvalidArgumentException('person_ids must be a list of IDs');
        }
        $ids = array_values(array_unique($ids));
        if ($ids === []) return [];
        $visible = self::database()->select('SELECT p.id FROM ('.self::VISIBLE.') p WHERE p.id IN (SELECT value FROM json_each(:ids))', ['user_id' => $userId, 'ids' => json_encode($ids)]);
        if (count($visible) !== count($ids)) throw new InvalidArgumentException('Invalid person');
        return $ids;
    }

    public static function syncEvent(int $eventId, array $ids): void
    {
        self::sync('event_person', 'event_id', $eventId, $ids);
    }

    public static function syncRoutine(int $routineId, array $ids): void
    {
        self::sync('routine_person', 'routine_id', $routineId, $ids);
    }

    private static function sync(string $table, string $column, int $id, array $ids): void
    {
        self::database()->execute("DELETE FROM $table WHERE $column=:id", ['id' => $id]);
        self::database()->execute("INSERT INTO $table ($column,person_id) SELECT :id,value FROM json_each(:ids)", ['id' => $id, 'ids' => json_encode($ids)]);
    }

    /**
     * Personas por evento en una sola consulta. Las sesiones de rutina heredan las de su rutina.
     *
     * @return array<int, array> event_id => [{id,user_id,name,color}]
     */
    public static function byEvent(array $eventIds): array
    {
        if ($eventIds === []) return [];
        $rows = self::database()->select(<<<'SQL'
            SELECT x.event_id, p.id, p.user_id, p.name, p.color
            FROM (
                SELECT ep.event_id, ep.person_id FROM event_person ep INNER JOIN event e ON e.id=ep.event_id
                WHERE e.routine_id IS NULL AND ep.event_id IN (SELECT value FROM json_each(:ids))
                UNION
                SELECT e.id, rp.person_id FROM event e INNER JOIN routine_person rp ON rp.routine_id=e.routine_id
                WHERE e.id IN (SELECT value FROM json_each(:ids))
            ) x
            INNER JOIN person p ON p.id=x.person_id
            ORDER BY p.name COLLATE NOCASE, p.id
        SQL, ['ids' => json_encode(array_values($eventIds))]);
        return self::group($rows, 'event_id');
    }

    /** @return array<int, array> routine_id => [{id,user_id,name,color}] */
    public static function byRoutine(array $routineIds): array
    {
        if ($routineIds === []) return [];
        $rows = self::database()->select(<<<'SQL'
            SELECT rp.routine_id, p.id, p.user_id, p.name, p.color
            FROM routine_person rp INNER JOIN person p ON p.id=rp.person_id
            WHERE rp.routine_id IN (SELECT value FROM json_each(:ids))
            ORDER BY p.name COLLATE NOCASE, p.id
        SQL, ['ids' => json_encode(array_values($routineIds))]);
        return self::group($rows, 'routine_id');
    }

    private static function group(array $rows, string $key): array
    {
        $grouped = [];
        foreach ($rows as $row) {
            $owner = (int)$row[$key];
            unset($row[$key]);
            $grouped[$owner][] = $row;
        }
        return $grouped;
    }
}
