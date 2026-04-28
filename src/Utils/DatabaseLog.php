<?php declare(strict_types=1);

namespace App\Utils;

class DatabaseLog
{
    private const SENSITIVE_KEYS = ['password', 'token'];

    private static ?array $config = null;
    private static string $base;

    public static function log(string $sql, array $data, float $timeMs): void
    {
        $config = self::config();

        if ($config['enabled'] !== true) {
            return;
        }

        $lines = ['# ['.REQUEST_ID.'] '.($_SERVER['REQUEST_URI'] ?? '-')];

        if ($config['backtrace']) {
            foreach (self::backtrace(intval($config['backtrace'])) as $frame) {
                $lines[] = '# '.$frame;
            }
        }

        if ($config['time']) {
            $lines[] = sprintf('# Time: %0.3f ms', $timeMs);
        }

        $lines[] = sprintf(
            '[%s] %s',
            date('Y-m-d H:i:s'),
            self::interpolate(self::normalizeSql($sql), self::mask($data)),
        );

        file_put_contents(
            self::file(),
            implode(PHP_EOL, $lines).PHP_EOL.PHP_EOL,
            FILE_APPEND | LOCK_EX,
        );
    }

    private static function config(): array
    {
        return self::$config ??= [
            'enabled' => Config::key('private', 'db_log_enabled'),
            'time' => Config::key('private', 'db_log_time'),
            'backtrace' => Config::key('private', 'db_log_backtrace'),
        ];
    }

    private static function backtrace(int $limit): array
    {
        $base = self::base();
        $frames = [];

        foreach (debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS) as $frame) {
            $file = $frame['file'] ?? null;

            if (empty($file) || (str_starts_with($file, $base) === false)) {
                continue;
            }

            if (self::isInternalFile($file)) {
                continue;
            }

            $frames[] = substr($file, strlen($base) + 1).'#'.($frame['line'] ?? '?');

            if (count($frames) >= $limit) {
                break;
            }
        }

        return $frames;
    }

    private static function isInternalFile(string $file): bool
    {
        return ($file === __FILE__) || ($file === self::base().'/src/Utils/Database.php');
    }

    private static function base(): string
    {
        return self::$base ??= dirname(dirname(__DIR__));
    }

    private static function normalizeSql(string $sql): string
    {
        return trim(preg_replace('/\s+/', ' ', trim($sql)), ';').';';
    }

    private static function interpolate(string $sql, array $data): string
    {
        if (empty($data)) {
            return $sql;
        }

        return preg_replace_callback('/:([a-zA-Z_][a-zA-Z0-9_]*)/', static function (array $match) use ($data): string {
            if (array_key_exists($match[1], $data) === false) {
                return $match[0];
            }

            return self::quote($data[$match[1]]);
        }, $sql);
    }

    private static function quote(mixed $value): string
    {
        if ($value === null) {
            return 'NULL';
        }

        if (is_bool($value)) {
            return $value ? '1' : '0';
        }

        if (is_int($value) || is_float($value)) {
            return strval($value);
        }

        return "'".str_replace("'", "''", strval($value))."'";
    }

    private static function mask(array $data): array
    {
        foreach ($data as $key => $value) {
            if (in_array(strtolower(strval($key)), self::SENSITIVE_KEYS, true)) {
                $data[$key] = '***';
            } elseif (is_array($value)) {
                $data[$key] = self::mask($value);
            }
        }

        return $data;
    }

    private static function file(): string
    {
        $file = self::base().'/logs/'.date('Y-m-d').'/db.log';

        Helper::mkdir($file, true);

        return $file;
    }
}
