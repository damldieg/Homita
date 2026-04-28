<?php declare(strict_types=1);

namespace App\Utils;

use Throwable;

class Error
{
    public static function report(Throwable $e): void
    {
        file_put_contents(static::file(), '['.date('Y-m-d H:i:s').'] '.$e->getMessage().PHP_EOL.$e->getTraceAsString().PHP_EOL, FILE_APPEND);
    }

    private static function file(): string
    {
        $file = dirname(dirname(__DIR__)).'/logs/'.date('Y-m-d').'/app.log';

        Helper::mkdir($file, true);

        return $file;
    }
}
