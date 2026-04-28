<?php declare(strict_types=1);

namespace App\Models;

class EventUser extends ModelAbstract
{
    public int $id;
    public int $event_id;
    public int $user_id;
    public int $alarm;
    public string $created_at;
    public string $updated_at;

    public static function apply(int $eventId, int $userId, ?int $alarm): void
    {
        if ($alarm === null) {
            self::removeAlarm($eventId, $userId);
        } else {
            self::setAlarm($eventId, $userId, $alarm);
        }
    }

    public static function setAlarm(int $eventId, int $userId, int $alarm): self
    {
        self::database()->execute(self::upsertSql(), [
            'event_id' => $eventId,
            'user_id' => $userId,
            'alarm' => max(0, $alarm),
        ]);

        return self::findByEventAndUser($eventId, $userId);
    }

    private static function upsertSql(): string
    {
        return <<<'SQL'
            INSERT INTO `event_user` (`event_id`, `user_id`, `alarm`)
            VALUES (:event_id, :user_id, :alarm)
            ON CONFLICT(`event_id`, `user_id`) DO UPDATE SET
                `alarm` = excluded.`alarm`,
                `updated_at` = CURRENT_TIMESTAMP
        SQL;
    }

    public static function removeAlarm(int $eventId, int $userId): void
    {
        self::database()->execute(self::removeAlarmSql(), [
            'event_id' => $eventId,
            'user_id' => $userId,
        ]);
    }

    private static function removeAlarmSql(): string
    {
        return <<<'SQL'
            DELETE FROM `event_user`
            WHERE `event_id` = :event_id
              AND `user_id` = :user_id
        SQL;
    }

    public static function findByEventAndUser(int $eventId, int $userId): self
    {
        return new self(self::database()->selectOneOrFail(self::findByEventAndUserSql(), [
            'event_id' => $eventId,
            'user_id' => $userId,
        ]));
    }

    private static function findByEventAndUserSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `event_user`
            WHERE `event_id` = :event_id
              AND `user_id` = :user_id
            LIMIT 1
        SQL;
    }
}
