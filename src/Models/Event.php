<?php declare(strict_types=1);

namespace App\Models;

use App\Utils\Helper;

class Event extends ModelAbstract
{
    public int $id;
    public int $calendar_id;
    public ?string $calendar_color = null;
    public ?string $calendar_name = null;
    public string $title;
    public string $date_at;
    public ?int $alarm = null;
    public string $created_at;
    public string $updated_at;

    public static function create(int $calendarId, string $title, string $dateAt): self
    {
        return self::findById(self::database()->insert(self::createSql(), [
            'calendar_id' => $calendarId,
            'title' => $title,
            'date_at' => $dateAt,
        ]));
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `event` (`calendar_id`, `title`, `date_at`)
            VALUES (:calendar_id, :title, :date_at)
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
            SELECT e.*,
                   c.`color` as `calendar_color`,
                   c.`name` as `calendar_name`
            FROM `event` e
            INNER JOIN `calendar` c ON c.`id` = e.`calendar_id`
            WHERE e.`id` = :id
            LIMIT 1
        SQL;
    }

    public static function findByCalendar(int $calendarId): array
    {
        $rows = self::database()->select(self::findByCalendarSql(), [
            'calendar_id' => $calendarId,
        ]);

        return array_map(static fn(array $row) => new self($row), $rows);
    }

    private static function findByCalendarSql(): string
    {
        return <<<'SQL'
            SELECT e.*,
                   c.`color` as `calendar_color`,
                   c.`name` as `calendar_name`
            FROM `event` e
            INNER JOIN `calendar` c ON c.`id` = e.`calendar_id`
            WHERE e.`calendar_id` = :calendar_id
            ORDER BY e.`date_at` ASC
        SQL;
    }

    public static function findByUser(int $userId): array
    {
        return self::findWithFilters($userId, []);
    }

    public static function findWithFilters(int $userId, array $filters): array
    {
        $params = ['user_id' => $userId];

        if ($value = self::getFilterInt($filters, 'calendar_id')) {
            $params['calendar_id'] = $value;
        }

        if ($value = self::getFilterString($filters, 'search')) {
            $params['search'] = '%'.$value.'%';
        }

        if ($value = self::getFilterTimestamp($filters, 'start_date')) {
            $params['start_date'] = $value;
        }

        if ($value = self::getFilterTimestamp($filters, 'end_date')) {
            $params['end_date'] = $value;
        }

        if ($value = self::getFilterInt($filters, 'limit')) {
            $params['limit'] = $value;
        }

        if ($value = self::getFilterInt($filters, 'offset')) {
            $params['offset'] = $value;
        }

        if ($value = self::getFilterString($filters, 'order_mode')) {
            $params['order_mode'] = $value;
        }

        if (($value = self::getFilterBool($filters, 'widget')) !== null) {
            $params['widget'] = intval($value);
        }

        $rows = self::database()->select(
            self::findWithFiltersSql($params),
            Helper::arrayDenyKeys($params, ['order_mode'])
        );

        return array_map(static fn(array $row) => new self($row), $rows);
    }

    private static function findWithFiltersSql(array $params): string
    {
        $base = <<<'SQL'
            SELECT e.*,
                   c.`color` as `calendar_color`,
                   c.`name` as `calendar_name`,
                   eu.`alarm` as `alarm`
            FROM `event` e
            INNER JOIN `calendar_user` cu ON cu.`calendar_id` = e.`calendar_id`
            INNER JOIN `calendar` c ON c.`id` = e.`calendar_id`
            LEFT JOIN `event_user` eu ON eu.`event_id` = e.`id` AND eu.`user_id` = cu.`user_id`
            WHERE cu.`user_id` = :user_id
        SQL;

        if (isset($params['calendar_id'])) {
            $base .= ' AND e.`calendar_id` = :calendar_id';
        }

        if (isset($params['search'])) {
            $base .= ' AND e.`title` LIKE :search';
        }

        if (isset($params['start_date'])) {
            $base .= ' AND e.`date_at` >= :start_date';
        }

        if (isset($params['end_date'])) {
            $base .= ' AND e.`date_at` <= :end_date';
        }

        if (isset($params['widget'])) {
            $base .= ' AND cu.`widget` = :widget';
        }

        $order = strtoupper($params['order_mode'] ?? 'ASC');

        if (in_array($order, ['ASC', 'DESC'], true) === false) {
            $order = 'ASC';
        }

        $base .= ' ORDER BY e.`date_at` '.$order;

        if (isset($params['limit'])) {
            $base .= ' LIMIT :limit';
        }

        if (isset($params['offset'])) {
            $base .= ' OFFSET :offset';
        }

        return $base;
    }

    public static function findByIdAndUser(int $id, int $userId): self
    {
        return new self(self::database()->selectOneOrFail(self::findByIdAndUserSql(), [
            'id' => $id,
            'user_id' => $userId,
        ]));
    }

    private static function findByIdAndUserSql(): string
    {
        return <<<'SQL'
            SELECT e.*,
                   eu.`alarm` as `alarm`
            FROM `event` e
            INNER JOIN `calendar_user` cu ON cu.`calendar_id` = e.`calendar_id`
            LEFT JOIN `event_user` eu ON eu.`event_id` = e.`id` AND eu.`user_id` = cu.`user_id`
            WHERE e.`id` = :id
              AND cu.`user_id` = :user_id
            LIMIT 1
        SQL;
    }

    public function update(string $title, string $dateAt): self
    {
        self::database()->execute(self::updateSql(), [
            'title' => $title,
            'date_at' => $dateAt,
            'id' => $this->id,
        ]);

        return self::findById($this->id);
    }

    private static function updateSql(): string
    {
        return <<<'SQL'
            UPDATE `event`
            SET `title` = :title,
                `date_at` = :date_at,
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
            DELETE FROM `event`
            WHERE `id` = :id
        SQL;
    }
}
