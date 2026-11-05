<?php declare(strict_types=1);

namespace App\Models;

use App\Utils\Database;

class Task extends ModelAbstract
{
    public int $id;
    public int $task_list_id;
    public ?string $task_list_color = null;
    public ?string $task_list_name = null;
    public string $title;
    public int $order;
    public ?string $completed_at = null;
    public string $created_at;
    public string $updated_at;

    public static function create(int $taskListId, string $title): self
    {
        return Database::transaction(static function () use ($taskListId, $title): self {
            $id = self::database()->insert(self::createSql(), [
                'task_list_id' => $taskListId,
                'title' => $title,
            ]);

            self::reorderByList($taskListId);

            return self::findById($id);
        });
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `task` (`task_list_id`, `title`)
            VALUES (:task_list_id, :title)
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
            SELECT t.*,
                   tl.`color` as `task_list_color`,
                   tl.`name` as `task_list_name`
            FROM `task` t
            INNER JOIN `task_list` tl ON tl.`id` = t.`task_list_id`
            WHERE t.`id` = :id
            LIMIT 1
        SQL;
    }

    public static function findByTaskList(int $taskListId): array
    {
        $rows = self::database()->select(self::findByTaskListSql(), [
            'task_list_id' => $taskListId,
        ]);

        return array_map(static fn(array $row) => new self($row), $rows);
    }

    public static function findByUser(int $userId): array
    {
        return self::findWithFilters($userId, []);
    }

    public static function findWithFilters(int $userId, array $filters): array
    {
        $params = ['user_id' => $userId];

        if ($value = self::getFilterInt($filters, 'task_list_id')) {
            $params['task_list_id'] = $value;
        }

        if (($value = self::getFilterBool($filters, 'widget')) !== null) {
            $params['widget'] = $value ? 1 : 0;
        }

        if (($value = self::getFilterBool($filters, 'dashboard')) !== null) {
            $params['dashboard'] = $value ? 1 : 0;
        }

        $rows = self::database()->select(self::findWithFiltersSql($params), $params);

        return array_map(static fn(array $row) => new self($row), $rows);
    }

    private static function findWithFiltersSql(array $params): string
    {
        $base = <<<'SQL'
            SELECT t.*,
                   tl.`color` as `task_list_color`,
                   tl.`name` as `task_list_name`
            FROM `task` t
            INNER JOIN `task_list` tl ON tl.`id` = t.`task_list_id`
            INNER JOIN `task_list_user` tlu ON tlu.`task_list_id` = t.`task_list_id`
            WHERE tlu.`user_id` = :user_id
        SQL;

        if (isset($params['task_list_id'])) {
            $base .= ' AND t.`task_list_id` = :task_list_id';
        }

        if (isset($params['widget'])) {
            $base .= ' AND tlu.`widget` = :widget';
        }

        if (isset($params['dashboard'])) {
            $base .= ' AND tlu.`dashboard` = :dashboard';
        }

        $base .= ' ORDER BY (t.`completed_at` IS NOT NULL) ASC, t.`order` ASC';

        return $base;
    }

    private static function findByTaskListSql(): string
    {
        return <<<'SQL'
            SELECT t.*,
                   tl.`color` as `task_list_color`,
                   tl.`name` as `task_list_name`
            FROM `task` t
            INNER JOIN `task_list` tl ON tl.`id` = t.`task_list_id`
            WHERE t.`task_list_id` = :task_list_id
            ORDER BY (t.`completed_at` IS NOT NULL) ASC,
                     t.`order` ASC
        SQL;
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
            SELECT t.*,
                tl.`color` as `task_list_color`,
                tl.`name` as `task_list_name`
            FROM `task` t
            INNER JOIN `task_list` tl ON tl.`id` = t.`task_list_id`
            INNER JOIN `task_list_user` tlu ON tlu.`task_list_id` = t.`task_list_id`
            WHERE (
                t.`id` = :id
                AND tlu.`user_id` = :user_id
            )
            LIMIT 1
        SQL;
    }

    public function update(string $title): self
    {
        return Database::transaction(function () use ($title): self {
            self::database()->execute(self::updateSql(), [
                'title' => $title,
                'id' => $this->id,
            ]);

            self::reorderByList($this->task_list_id);

            return self::findById($this->id);
        });
    }

    private static function updateSql(): string
    {
        return <<<'SQL'
            UPDATE `task`
            SET `title` = :title,
                `updated_at` = CURRENT_TIMESTAMP
            WHERE `id` = :id
        SQL;
    }

    public function setCompleted(bool $completed): self
    {
        self::database()->execute($completed ? self::markCompletedSql() : self::markIncompleteSql(), [
            'id' => $this->id,
        ]);

        return self::findById($this->id);
    }

    private static function markCompletedSql(): string
    {
        return <<<'SQL'
            UPDATE `task`
            SET `completed_at` = CURRENT_TIMESTAMP,
                `updated_at` = CURRENT_TIMESTAMP
            WHERE `id` = :id
        SQL;
    }

    private static function markIncompleteSql(): string
    {
        return <<<'SQL'
            UPDATE `task`
            SET `completed_at` = NULL,
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
            DELETE FROM `task`
            WHERE `id` = :id
        SQL;
    }

    public static function reorderByList(int $taskListId): void
    {
        self::database()->execute(self::reorderByListSql(), [
            'task_list_id' => $taskListId,
            'task_list_id_scope' => $taskListId,
        ]);
    }

    private static function reorderByListSql(): string
    {
        return <<<'SQL'
            UPDATE `task`
            SET `order` = (
                SELECT rn FROM (
                    SELECT t2.`id`, ROW_NUMBER() OVER (
                        ORDER BY
                            CASE WHEN tl.`sort` = 'title' THEN t2.`title` END ASC,
                            CASE WHEN tl.`sort` IN ('updated_at','custom') THEN t2.`updated_at` END DESC
                    ) AS rn
                    FROM `task` t2
                    INNER JOIN `task_list` tl ON tl.`id` = t2.`task_list_id`
                    WHERE t2.`task_list_id` = :task_list_id_scope
                ) ranked
                WHERE ranked.`id` = `task`.`id`
            )
            WHERE `task_list_id` = :task_list_id
        SQL;
    }

    public function moveToPosition(int $position): self
    {
        return Database::transaction(function () use ($position): self {
            $tasks = self::database()->select(self::idsByListOrderedSql(), [
                'task_list_id' => $this->task_list_id,
            ]);

            $ids = array_values(array_filter(
                array_column($tasks, 'id'),
                fn($id) => intval($id) !== $this->id,
            ));

            $position = max(0, min($position, count($ids)));

            array_splice($ids, $position, 0, [$this->id]);

            foreach ($ids as $index => $id) {
                self::database()->execute(self::setOrderSql(), [
                    'order' => $index + 1,
                    'id' => intval($id),
                ]);
            }

            return self::findById($this->id);
        });
    }

    private static function idsByListOrderedSql(): string
    {
        return <<<'SQL'
            SELECT `id`
            FROM `task`
            WHERE `task_list_id` = :task_list_id
            ORDER BY `order` ASC, `id` ASC
        SQL;
    }

    private static function setOrderSql(): string
    {
        return <<<'SQL'
            UPDATE `task`
            SET `order` = :order
            WHERE `id` = :id
        SQL;
    }
}
