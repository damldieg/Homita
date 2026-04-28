<?php declare(strict_types=1);

namespace App\Models;

class Calendar extends ModelAbstract
{
    public int $id;
    public string $name;
    public string $color;
    public string $token;
    public string $created_at;
    public string $updated_at;
    public int $upcoming_event_count = 0;
    public int $widget = 1;

    public static function create(string $name, string $color = '#6923E2'): self
    {
        return self::findById(self::database()->insert(self::createSql(), [
            'name' => $name,
            'color' => $color,
            'token' => self::token(),
        ]));
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `calendar` (`name`, `color`, `token`)
            VALUES (:name, :color, :token)
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
            FROM `calendar`
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
            FROM `calendar`
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
            FROM `calendar`
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
            SELECT c.*,
                   cu.`widget` AS `widget`,
                   COALESCE((
                       SELECT COUNT(*)
                       FROM `event` e
                       WHERE e.`calendar_id` = c.`id`
                         AND e.`date_at` >= CURRENT_TIMESTAMP
                   ), 0) AS `upcoming_event_count`
            FROM `calendar` c
            INNER JOIN `calendar_user` cu ON cu.`calendar_id` = c.`id`
            WHERE cu.`user_id` = :user_id
            ORDER BY c.`name` ASC
        SQL;
    }

    public function update(string $name, string $color): self
    {
        self::database()->execute(self::updateSql(), [
            'name' => $name,
            'color' => $color,
            'id' => $this->id,
        ]);

        return self::findById($this->id);
    }

    private static function updateSql(): string
    {
        return <<<'SQL'
            UPDATE `calendar`
            SET `name` = :name,
                `color` = :color,
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
            DELETE FROM `calendar`
            WHERE `id` = :id
        SQL;
    }
}
