<?php declare(strict_types=1);

namespace App\Utils;

use Throwable;

class Helper
{
    public static function arrayDenyKeys(array $array, array $keys): array
    {
        return array_diff_key($array, array_flip($keys));
    }

    public static function logger(mixed $data): void
    {
        Logger::info($data);
    }

    public static function mkdir(string $dir, bool $file = false): string
    {
        if ($file) {
            $dir = dirname($dir);
        }

        usleep(rand(10, 100));

        clearstatcache(true, $dir);

        if (is_dir($dir)) {
            return $dir;
        }

        try {
            mkdir($dir, 0o755, true);
        } catch (Throwable) {
        }

        return $dir;
    }
}
