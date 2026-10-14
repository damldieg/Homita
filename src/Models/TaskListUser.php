<?php declare(strict_types=1);

namespace App\Models;

class TaskListUser extends ModelAbstract
{
    public int $id;
    public int $task_list_id;
    public int $user_id;
    public string $role;
    public int $widget = 1;
    public int $dashboard = 1;
    public string $created_at;

    public static function create(int $taskListId, int $userId, string $role, bool $widget = true): self
    {
        return self::findById(self::database()->insert(self::createSql(), [
            'task_list_id' => $taskListId,
            'user_id' => $userId,
            'role' => $role,
            'widget' => intval($widget),
        ]));
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `task_list_user` (`task_list_id`, `user_id`, `role`, `widget`)
            VALUES (:task_list_id, :user_id, :role, :widget)
        SQL;
    }

    public static function setWidget(int $taskListId, int $userId, bool $widget): void
    {
        self::database()->execute(self::setWidgetSql(), [
            'task_list_id' => $taskListId,
            'user_id' => $userId,
            'widget' => intval($widget),
        ]);
    }

    private static function setWidgetSql(): string
    {
        return <<<'SQL'
            UPDATE `task_list_user`
            SET `widget` = :widget
            WHERE `task_list_id` = :task_list_id
              AND `user_id` = :user_id
        SQL;
    }

    /** Marca para el dashboard exactamente los ids indicados entre los del usuario. */
    public static function setDashboard(int $userId, array $ids): void
    {
        self::database()->execute(self::setDashboardSql(), [
            'user_id' => $userId,
            'ids' => json_encode(array_values($ids)),
        ]);
    }

    private static function setDashboardSql(): string
    {
        return <<<'SQL'
            UPDATE `task_list_user`
            SET `dashboard` = (`task_list_id` IN (SELECT `value` FROM json_each(:ids)))
            WHERE `user_id` = :user_id
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
            FROM `task_list_user`
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
            FROM `task_list_user`
            WHERE `user_id` = :user_id
        SQL;
    }

    public static function exists(int $taskListId, int $userId): bool
    {
        return boolval(self::database()->selectOne(self::existsSql(), [
            'task_list_id' => $taskListId,
            'user_id' => $userId,
        ]));
    }

    private static function existsSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `task_list_user`
            WHERE `task_list_id` = :task_list_id
              AND `user_id` = :user_id
            LIMIT 1
        SQL;
    }

    public static function check(int $taskListId, int $userId): self
    {
        return new self(self::database()->selectOneOrFail(self::checkSql(), [
            'task_list_id' => $taskListId,
            'user_id' => $userId,
        ]));
    }

    private static function checkSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `task_list_user`
            WHERE `task_list_id` = :task_list_id
              AND `user_id` = :user_id
            LIMIT 1
        SQL;
    }

    public static function findUsersByTaskList(int $taskListId): array
    {
        return self::database()->select(self::findUsersByTaskListSql(), [
            'task_list_id' => $taskListId,
        ]);
    }

    private static function findUsersByTaskListSql(): string
    {
        return <<<'SQL'
            SELECT tlu.id as tlu_id, u.id as user_id, u.name, u.email, tlu.role
            FROM `task_list_user` tlu
            INNER JOIN `user` u ON tlu.user_id = u.id
            WHERE tlu.task_list_id = :task_list_id
            ORDER BY tlu.role ASC, u.name ASC
        SQL;
    }

    public static function removeUser(int $taskListId, int $userIdToRemove): void
    {
        self::database()->execute(self::removeUserSql(), [
            'task_list_id' => $taskListId,
            'user_id' => $userIdToRemove,
        ]);
    }

    private static function removeUserSql(): string
    {
        return <<<'SQL'
            DELETE FROM `task_list_user`
            WHERE `task_list_id` = :task_list_id
              AND `user_id` = :user_id
        SQL;
    }
}
