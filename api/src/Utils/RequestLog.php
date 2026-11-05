<?php declare(strict_types=1);

namespace App\Utils;

class RequestLog
{
    private const SENSITIVE_KEYS = ['password', 'token', 'authorization'];

    public static function write(): void
    {
        file_put_contents(self::file(), self::line().PHP_EOL, FILE_APPEND);
    }

    private static function line(): string
    {
        return sprintf(
            '[%s] %s %s %s %s %s',
            date('Y-m-d H:i:s'),
            self::ip(),
            self::method(),
            self::uri(),
            self::encode(self::query()),
            self::encode(self::body()),
        );
    }

    private static function ip(): string
    {
        return $_SERVER['REMOTE_ADDR'] ?? '-';
    }

    private static function method(): string
    {
        return $_SERVER['REQUEST_METHOD'] ?? 'GET';
    }

    private static function uri(): string
    {
        return strtok($_SERVER['REQUEST_URI'] ?? '/', '?');
    }

    private static function query(): array
    {
        return self::mask($_GET);
    }

    private static function body(): array
    {
        $raw = file_get_contents('php://input') ?: '';

        if (empty($raw)) {
            return self::mask($_POST);
        }

        $decoded = json_decode($raw, true);

        return is_array($decoded) ? self::mask($decoded) : [];
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

    private static function encode(array $data): string
    {
        return empty($data) ? '-' : json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    private static function file(): string
    {
        $file = dirname(dirname(__DIR__)).'/logs/'.date('Y-m-d').'/requests.log';

        Helper::mkdir($file, true);

        return $file;
    }
}
