<?php declare(strict_types=1);

namespace App\Utils;

use Exception;
use PDO;
use Throwable;

class Database
{
    private static string $name = 'database';
    private static string $file;

    private static PDO $instance;

    private static function getInstance(): PDO
    {
        if (isset(self::$instance)) {
            return self::$instance;
        }

        self::$instance = new PDO(
            'sqlite:'.self::file(),
            null,
            null,
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );

        self::$instance->exec('PRAGMA foreign_keys = ON;');

        return self::$instance;
    }

    public function selectOne(string $sql, array $data = []): ?array
    {
        $start = microtime(true);

        $query = self::getInstance()->prepare(trim($sql));
        $query->execute($data);

        DatabaseLog::log($sql, $data, (microtime(true) - $start) * 1000);

        return $query->fetch() ?: null;
    }

    public function selectOneOrFail(string $sql, array $data = [])
    {
        $data = static::selectOne($sql, $data);

        if (empty($data)) {
            throw new Exception('Not Found');
        }

        return $data;
    }

    public function select(string $sql, array $data = []): array
    {
        $start = microtime(true);

        $query = self::getInstance()->prepare(trim($sql));
        $query->execute($data);

        DatabaseLog::log($sql, $data, (microtime(true) - $start) * 1000);

        return $query->fetchAll();
    }

    public function insert(string $sql, array $data = []): int
    {
        $start = microtime(true);

        $db = self::getInstance();
        $db->prepare(trim($sql))->execute($data);

        DatabaseLog::log($sql, $data, (microtime(true) - $start) * 1000);

        return intval($db->lastInsertId());
    }

    public function execute(string $sql, array $data = []): void
    {
        $start = microtime(true);

        $query = self::getInstance()->prepare(trim($sql));

        if ($data) {
            $query->execute($data);
        } else {
            $query->execute();
        }

        DatabaseLog::log($sql, $data, (microtime(true) - $start) * 1000);
    }

    public static function exec(string $sql): void
    {
        $start = microtime(true);

        self::getInstance()->exec(trim($sql));

        DatabaseLog::log($sql, [], (microtime(true) - $start) * 1000);
    }

    public static function transaction(callable $callback): mixed
    {
        $db = self::getInstance();
        $db->beginTransaction();

        try {
            $result = $callback();

            $db->commit();

            return $result;
        } catch (Throwable $e) {
            $db->rollBack();

            throw $e;
        }
    }

    public static function name(string $name): void
    {
        self::$name = $name;
    }

    private static function file(): string
    {
        return self::$file ??= dirname(dirname(__DIR__)).'/db/'.self::$name.'.sqlite';
    }
}
