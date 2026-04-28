<?php declare(strict_types=1);

require dirname(__DIR__).'/src/autoload.php';

use App\Utils\Error;
use App\Utils\RequestLog;

RequestLog::write();

try {
    require dirname(__DIR__).'/src/Controllers/router.php';
} catch (Throwable $e) {
    Error::report($e);
}
