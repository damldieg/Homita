<?php declare(strict_types=1);

namespace App\Models;

use RuntimeException;
use App\Utils\Database;

class Migration extends ModelAbstract
{
    public int $id;
    public string $name;
    public string $applied_at;

    public static function setup(): void
    {
        static::setupDatabasePath();
        static::setupDatabaseFile();
        static::setupMigrationsTable();
    }

    private static function setupDatabasePath(): void
    {
        $db = dirname(dirname(__DIR__)).'/db';

        if (is_dir($db) === false) {
            mkdir($db, 0755, true);
        }
    }

    private static function setupDatabaseFile(): void
    {
        $file = dirname(dirname(__DIR__)).'/db/database.sqlite';

        if (is_file($file) === false) {
            touch($file);
        }
    }

    private static function setupMigrationsTable(): void
    {
        Database::exec(self::setupMigrationsTableSql());
    }

    private static function setupMigrationsTableSql(): string
    {
        return <<<'SQL'
            CREATE TABLE IF NOT EXISTS `migration` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT,
                `name` TEXT NOT NULL UNIQUE,
                `applied_at` DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        SQL;
    }

    public static function apply(string $name): self
    {
        $file = self::path().'/'.$name.'.sql';

        if (is_file($file) === false) {
            throw new RuntimeException(sprintf('Migration file not found: %s', $file));
        }

        Database::exec('PRAGMA foreign_keys = OFF');

        try {
            return Database::transaction(static function () use ($name, $file): self {
                Database::exec(file_get_contents($file));

                return self::create($name);
            });
        } finally {
            Database::exec('PRAGMA foreign_keys = ON');
        }
    }

    private static function path(): string
    {
        return dirname(dirname(__DIR__)).'/migrations';
    }

    public static function names(): array
    {
        return array_column(self::database()->select(self::namesSql()), 'name');
    }

    private static function namesSql(): string
    {
        return <<<'SQL'
            SELECT `name`
            FROM `migration`
        SQL;
    }

    public static function create(string $name): self
    {
        return self::findById(self::database()->insert(self::createSql(), [
            'name' => $name,
        ]));
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `migration` (`name`)
            VALUES (:name)
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
            FROM `migration`
            WHERE `id` = :id
            LIMIT 1
        SQL;
    }
}
