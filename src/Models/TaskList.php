<?php declare(strict_types=1);

namespace App\Models;

class TaskList extends ModelAbstract
{
    public int $id;
    public string $name;
    public string $color;
    public string $token;
    public string $sort;
    public string $created_at;
    public string $updated_at;
    public int $pending_task_count = 0;
    public int $widget = 1;

    public static function create(string $name, string $color = '#6923E2', string $sort = 'updated_at'): self
    {
        return self::findById(self::database()->insert(self::createSql(), [
            'name' => $name,
            'color' => $color,
            'token' => self::token(),
            'sort' => $sort,
        ]));
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `task_list` (`name`, `color`, `token`, `sort`)
            VALUES (:name, :color, :token, :sort)
        SQL;
    }

    private static function token(): string
    {
        while (true) {
            $token = strtoupper(bin2hex(random_bytes(4)));

            if (self::tokenExists($token) === false) {
                return $token;
            }
        }
    }

    private static function tokenExists(string $token): bool
    {
        return boolval(self::database()->selectOne(self::tokenExistsSql(), [
            'token' => $token,
        ]));
    }

    private static function tokenExistsSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `task_list`
            WHERE `token` = :token
            LIMIT 1
        SQL;
    }

    public static function findById(int $id): self
    {
        return new self(self::database()->selectOneOrFail(self::findByIdSql(), [
            'id' => $id,
        ]));
    }

    private static function findByIdSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `task_list`
            WHERE `id` = :id
            LIMIT 1
        SQL;
    }

    public static function findByToken(string $token): self
    {
        return new self(self::database()->selectOneOrFail(self::findByTokenSql(), [
            'token' => $token,
        ]));
    }

    private static function findByTokenSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `task_list`
            WHERE `token` = :token
            LIMIT 1
        SQL;
    }

    public static function findByUser(int $userId): array
    {
        $rows = self::database()->select(self::findByUserSql(), [
            'user_id' => $userId,
        ]);

        return array_map(static fn(array $row) => new self($row), $rows);
    }

    private static function findByUserSql(): string
    {
        return <<<'SQL'
            SELECT tl.*,
                   tlu.`widget` AS `widget`,
                   COALESCE((
                       SELECT COUNT(*)
                       FROM `task` t
                       WHERE t.`task_list_id` = tl.`id`
                         AND t.`completed_at` IS NULL
                   ), 0) AS `pending_task_count`
            FROM `task_list` tl
            INNER JOIN `task_list_user` tlu ON tlu.`task_list_id` = tl.`id`
            WHERE tlu.`user_id` = :user_id
            ORDER BY tl.`name` ASC
        SQL;
    }

    public function update(string $name, string $color, string $sort): self
    {
        self::database()->execute(self::updateSql(), [
            'name' => $name,
            'color' => $color,
            'sort' => $sort,
            'id' => $this->id,
        ]);

        if ($sort !== 'custom') {
            Task::reorderByList($this->id);
        }

        return self::findById($this->id);
    }

    private static function updateSql(): string
    {
        return <<<'SQL'
            UPDATE `task_list`
            SET `name` = :name,
                `color` = :color,
                `sort` = :sort,
                `updated_at` = CURRENT_TIMESTAMP
            WHERE `id` = :id
        SQL;
    }

    public function delete(): void
    {
        self::database()->execute(self::deleteSql(), [
            'id' => $this->id,
        ]);
    }

    private static function deleteSql(): string
    {
        return <<<'SQL'
            DELETE FROM `task_list`
            WHERE `id` = :id
        SQL;
    }
}
