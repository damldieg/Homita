<?php declare(strict_types=1);

namespace App\Models;

class CalendarUser extends ModelAbstract
{
    public int $id;
    public int $calendar_id;
    public int $user_id;
    public string $role;
    public int $widget = 1;
    public string $created_at;

    public static function create(int $calendarId, int $userId, string $role, bool $widget = true): self
    {
        return self::findById(self::database()->insert(self::createSql(), [
            'calendar_id' => $calendarId,
            'user_id' => $userId,
            'role' => $role,
            'widget' => intval($widget),
        ]));
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `calendar_user` (`calendar_id`, `user_id`, `role`, `widget`)
            VALUES (:calendar_id, :user_id, :role, :widget)
        SQL;
    }

    public static function setWidget(int $calendarId, int $userId, bool $widget): void
    {
        self::database()->execute(self::setWidgetSql(), [
            'calendar_id' => $calendarId,
            'user_id' => $userId,
            'widget' => intval($widget),
        ]);
    }

    private static function setWidgetSql(): string
    {
        return <<<'SQL'
            UPDATE `calendar_user`
            SET `widget` = :widget
            WHERE `calendar_id` = :calendar_id
              AND `user_id` = :user_id
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
            FROM `calendar_user`
            WHERE `id` = :id
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
            SELECT *
            FROM `calendar_user`
            WHERE `user_id` = :user_id
        SQL;
    }

    public static function exists(int $calendarId, int $userId): bool
    {
        return boolval(self::database()->selectOne(self::existsSql(), [
            'calendar_id' => $calendarId,
            'user_id' => $userId,
        ]));
    }

    private static function existsSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `calendar_user`
            WHERE `calendar_id` = :calendar_id
              AND `user_id` = :user_id
            LIMIT 1
        SQL;
    }

    public static function check(int $calendarId, int $userId): self
    {
        return new self(self::database()->selectOneOrFail(self::checkSql(), [
            'calendar_id' => $calendarId,
            'user_id' => $userId,
        ]));
    }

    private static function checkSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `calendar_user`
            WHERE `calendar_id` = :calendar_id
              AND `user_id` = :user_id
            LIMIT 1
        SQL;
    }

    public static function checkRole(int $calendarId, int $userId): self
    {
        $instance = self::check($calendarId, $userId);
        if ($instance->role !== 'owner') {
            throw new \Exception('Only owner can perform this action');
        }
        return $instance;
    }

    public static function findUsersByCalendar(int $calendarId): array
    {
        return self::database()->select(self::findUsersByCalendarSql(), [
            'calendar_id' => $calendarId,
        ]);
    }

    private static function findUsersByCalendarSql(): string
    {
        return <<<'SQL'
            SELECT cu.id as cu_id, u.id as user_id, u.name, u.email, cu.role
            FROM `calendar_user` cu
            INNER JOIN `user` u ON cu.user_id = u.id
            WHERE cu.calendar_id = :calendar_id
            ORDER BY cu.role ASC, u.name ASC
        SQL;
    }

    public static function removeUser(int $calendarId, int $userIdToRemove): void
    {
        self::database()->execute(self::removeUserSql(), [
            'calendar_id' => $calendarId,
            'user_id' => $userIdToRemove,
        ]);
    }

    private static function removeUserSql(): string
    {
        return <<<'SQL'
            DELETE FROM `calendar_user`
            WHERE `calendar_id` = :calendar_id
              AND `user_id` = :user_id
        SQL;
    }
}
