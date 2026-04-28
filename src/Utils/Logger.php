<?php declare(strict_types=1);

namespace App\Utils;

class Logger
{
    public static function info(mixed $data): void
    {
        file_put_contents(static::file(), '['.date('Y-m-d H:i:s').'] '.static::message($data).PHP_EOL, FILE_APPEND);
    }

    protected static function message(mixed $data): string
    {
        if (is_scalar($data)) {
            return $data;
        }

        if (is_object($data) && method_exists($data, 'toArray')) {
            $data = $data->toArray();
        }

        return json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    }

    private static function file(): string
    {
        $file = dirname(dirname(__DIR__)).'/logs/'.date('Y-m-d').'/app.log';

        Helper::mkdir($file, true);

        return $file;
    }
}
