<?php declare(strict_types=1);

require dirname(__DIR__).'/autoload.php';

use App\Models\Migration;

Migration::setup();

$migrations = dirname(dirname(__DIR__)).'/migrations';
$applied = Migration::names();
$count = 0;

foreach (glob($migrations.'/*.sql') as $file) {
    $name = basename($file, '.sql');

    if (in_array($name, $applied, true)) {
        continue;
    }

    echo sprintf('Applying %s.sql...', $name);

    Migration::apply($name);

    echo " OK\n";

    $count++;
}

if ($count === 0) {
    echo "Nothing to migrate.\n";
} else {
    echo sprintf("Applied %d migration%s.\n", $count, $count === 1 ? '' : 's');
}
