<?php declare(strict_types=1);

require dirname(__DIR__).'/src/autoload.php';

use App\Models\Calendar;
use App\Models\CalendarUser;
use App\Models\Event;
use App\Models\Task;
use App\Models\TaskList;
use App\Models\TaskListUser;
use App\Utils\Database;
use App\Utils\DatabaseLog;

function check(bool $condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

function flags(array $models): array {
    return array_map(static fn($model) => $model->dashboard, $models);
}

$file = tempnam(sys_get_temp_dir(), 'planify-dashboard-');
register_shutdown_function(static fn() => unlink($file));
$pdo = new PDO('sqlite:'.$file, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC, PDO::ATTR_EMULATE_PREPARES => false]);
$pdo->exec('PRAGMA foreign_keys = ON');
new ReflectionProperty(Database::class, 'instance')->setValue(null, $pdo);
new ReflectionProperty(DatabaseLog::class, 'config')->setValue(null, ['enabled' => false]);
foreach (glob(dirname(__DIR__).'/migrations/*.sql') as $migration) $pdo->exec(file_get_contents($migration));
// El calendario 1 y la lista 1 se comparten entre los usuarios 1 y 2
$pdo->exec("INSERT INTO user (id,name,email,password,token) VALUES (1,'Owner','a@b','x','a'),(2,'Member','c@d','x','b');
    INSERT INTO calendar (id,name,token) VALUES (1,'Home','h'),(2,'Work','w');
    INSERT INTO calendar_user (calendar_id,user_id,role) VALUES (1,1,'owner'),(2,1,'owner'),(1,2,'viewer');
    INSERT INTO task_list (id,name,token) VALUES (1,'Shopping','s'),(2,'Chores','c');
    INSERT INTO task_list_user (task_list_id,user_id,role) VALUES (1,1,'owner'),(2,1,'owner'),(1,2,'viewer')");

check(flags(Calendar::findByUser(1)) === [1, 1] && flags(TaskList::findByUser(1)) === [1, 1], 'Everything is shown by default');

$tomorrow = new DateTimeImmutable('tomorrow', new DateTimeZone('UTC'));
$home = Event::create(1, 'Dinner', $tomorrow->format('Y-m-d').' 20:00:00');
Event::create(2, 'Meeting', $tomorrow->format('Y-m-d').' 09:00:00');
Task::create(1, 'Milk');
Task::create(2, 'Laundry');

CalendarUser::setDashboard(1, [1]);
TaskListUser::setDashboard(1, [1]);
check(array_column(array_map(fn($c) => $c->toArray(), Calendar::findByUser(1)), 'dashboard', 'name') === ['Home' => 1, 'Work' => 0], 'Only the given calendars stay on the dashboard');
check(array_map(fn($e) => $e->id, Event::findWithFilters(1, ['dashboard' => 'true'])) === [$home->id], 'Event filter keeps dashboard calendars');
check(count(Event::findWithFilters(1, ['dashboard' => 'false'])) === 1, 'Event filter can list the hidden ones');
check(array_map(fn($t) => $t->title, Task::findWithFilters(1, ['dashboard' => 'true'])) === ['Milk'], 'Task filter keeps dashboard lists');
check(count(Event::findWithFilters(1, [])) === 2, 'Without the filter nothing changes');

check(flags(Calendar::findByUser(2)) === [1] && count(Event::findWithFilters(2, ['dashboard' => 'true'])) === 1, 'The selection is per user');

CalendarUser::setDashboard(1, []);
TaskListUser::setDashboard(1, [2, 1]);
check(Event::findWithFilters(1, ['dashboard' => 'true']) === [], 'An empty list hides every calendar');
check(flags(TaskList::findByUser(1)) === [1, 1], 'Several lists can be selected');
echo "Dashboard behavioral checks passed\n";
