<?php declare(strict_types=1);

require dirname(__DIR__).'/src/autoload.php';

use App\Models\Event;
use App\Models\EventUser;
use App\Models\Routine;
use App\Utils\Database;
use App\Utils\DatabaseLog;

function check(bool $condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

$file = tempnam(sys_get_temp_dir(), 'planify-routine-');
$originalPid = getmypid();
register_shutdown_function(static function () use ($file, $originalPid) { if (getmypid() === $originalPid) unlink($file); });
$pdo = new PDO('sqlite:'.$file, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
$pdo->exec('PRAGMA foreign_keys = ON');
new ReflectionProperty(Database::class, 'instance')->setValue(null, $pdo);
new ReflectionProperty(DatabaseLog::class, 'config')->setValue(null, ['enabled' => false]);
foreach (glob(dirname(__DIR__).'/migrations/*.sql') as $migration) {
    if (basename($migration) === '0006_routine.sql') {
        $pdo->exec("INSERT INTO user (id,name,email,password,token) VALUES (99,'Legacy','legacy@example.com','x','legacy'); INSERT INTO calendar (id,name,token) VALUES (99,'Legacy','legacy'); INSERT INTO event (id,calendar_id,title,date_at) VALUES (99,99,'Legacy','2000-01-01 10:00:00'); INSERT INTO event_user (event_id,user_id,alarm) VALUES (99,99,42)");
    }
    $pdo->exec(file_get_contents($migration));
}
check((int)$pdo->query('SELECT alarm FROM event_user WHERE event_id=99')->fetchColumn() === 42, 'Migration preserves existing reminders');
$pdo->exec('DELETE FROM calendar WHERE id=99; DELETE FROM user WHERE id=99');
$pdo->exec("INSERT INTO user (id,name,email,password,token) VALUES (1,'Owner','a@b','x','a'),(2,'Member','c@d','x','b'),(3,'Other','e@f','x','c'); INSERT INTO calendar (id,name,token) VALUES (1,'Training','c'); INSERT INTO calendar_user (calendar_id,user_id,role) VALUES (1,1,'owner'),(1,2,'viewer')");
$today = new DateTimeImmutable('today', new DateTimeZone('UTC'));
$data = ['title' => 'Training', 'days' => [1,3,5], 'time' => '23:59', 'start_date' => $today->format('Y-m-d'), 'end_date' => $today->modify('+20 days')->format('Y-m-d'), 'active' => true];
foreach ([['days' => []], ['days' => [0,8]], ['days' => ['1']], ['time' => '24:00'], ['start_date' => '2026-02-30'], ['end_date' => '2000-01-01'], ['title' => []], ['active' => 'yes']] as $invalid) {
    try { Routine::validate(array_replace($data, $invalid)); throw new RuntimeException('Invalid routine accepted'); }
    catch (InvalidArgumentException) {}
}
try { Routine::create(1, 3, $data, 'UTC'); throw new RuntimeException('Outsider created routine'); }
catch (Exception $error) { check($error->getMessage() === 'Not Found', 'Creation denied to outsider'); }
check((bool)Routine::cutoff('Etc/UTC'), 'IANA backward-compatible mobile timezone accepted');
try { Routine::cutoff('Invalid/Zone'); throw new RuntimeException('Invalid timezone accepted'); }
catch (InvalidArgumentException) {}
$routine = Routine::create(1, 1, $data + ['alarm' => 15], 'UTC');
$events = Event::findWithFilters(1, []);
check(count($events) > 0, 'Sessions generated');
$plain = Event::create(1, 'Plain event', $today->modify('+1 day')->format('Y-m-d').' 10:00:00');
check(array_map(fn($event) => $event->id, Event::findWithFilters(1, ['routine' => 'false'])) === [$plain->id], 'Routine filter false returns only regular events');
check(count(Event::findWithFilters(1, ['routine' => 'true'])) === count($events), 'Routine filter true returns only sessions');
$plain->delete();
$countBefore = $pdo->query('SELECT COUNT(*) FROM event')->fetchColumn();
foreach ([App\Controllers\EventCreate::class, App\Controllers\EventUpdate::class] as $class) {
    $controller = new ReflectionClass($class)->newInstanceWithoutConstructor();
    new ReflectionProperty(App\Controllers\ControllerAbstract::class, 'input')->setValue($controller, ['calendar_id' => 1, 'id' => $events[0]->id, 'title' => 'Rejected edit', 'date_at' => $events[0]->date_at, 'alarm' => -1, 'timezone' => 'UTC']);
    $controller->setUser(new App\Models\User($pdo->query('SELECT * FROM user WHERE id=1')->fetch()));
    try { $controller->handle(); throw new RuntimeException('Invalid event alarm accepted'); }
    catch (InvalidArgumentException) {}
    check($pdo->query('SELECT COUNT(*) FROM event')->fetchColumn() === $countBefore, 'Rejected alarm does not create an event');
    check(Event::findByIdAndUser($events[0]->id, 1)->title === 'Training', 'Rejected alarm does not edit the event');
    check((int)$pdo->query('SELECT COUNT(*) FROM routine_exception')->fetchColumn() === 0, 'Rejected alarm does not create an exception');
}
foreach ($events as $event) {
    check(in_array((int)new DateTimeImmutable($event->date_at)->format('N'), [1,3,5]), 'Selected weekdays only');
    check(substr($event->date_at, 0, 10) <= $data['end_date'], 'Inclusive end respected');
    check($event->alarm === 15, 'Creator routine alarm');
}
check(Event::findWithFilters(2, [])[0]->alarm === null, 'Other users not alerted');
$ids = array_column(array_map(fn($e) => $e->toArray(), $events), 'id');
Routine::materializeForUser(1, 'UTC');
check($ids === array_column(array_map(fn($e) => $e->toArray(), Event::findWithFilters(1, [])), 'id'), 'Repeated generation stable');
try { Routine::findByIdAndUser($routine->id, 3); throw new RuntimeException('Access allowed'); } catch (Exception $e) { check($e->getMessage() === 'Not Found', 'Outsider denied'); }
check(count(Routine::findByUser(2, 'UTC')) === 1, 'Member routine access');
// Separate SQLite connections must serialize simultaneous generation without duplicate sessions.
if (function_exists('pcntl_fork')) {
    $missing = $events[array_key_last($events)];
    $pdo->exec('DELETE FROM event WHERE id = '.$missing->id);
    $children = [];
    for ($i=0; $i<3; $i++) {
        $pid = pcntl_fork();
        if ($pid === 0) {
            $connection = new PDO('sqlite:'.$file, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
            $connection->exec('PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000');
            new ReflectionProperty(Database::class, 'instance')->setValue(null, $connection);
            for ($j=0; $j<3; $j++) Routine::materializeForUser(1, 'UTC');
            exit(0);
        }
        check($pid > 0, 'Fork succeeded');
        $children[] = $pid;
    }
    foreach ($children as $pid) { pcntl_waitpid($pid, $status); check(pcntl_wifexited($status) && pcntl_wexitstatus($status) === 0, 'Concurrent generator completed'); }
    check(count(Event::findWithFilters(1, [])) === count($ids), 'Concurrent generation creates no duplicates');
    $restoredIds = $pdo->query("SELECT id FROM event WHERE routine_id=".$routine->id." AND routine_date='".$missing->routine_date."'")->fetchAll(PDO::FETCH_COLUMN);
    check(count($restoredIds) === 1, 'Concurrent generation restores one missing occurrence');
    $retainedIds = $pdo->query("SELECT id FROM event WHERE routine_id=".$routine->id." AND routine_date!='".$missing->routine_date."' ORDER BY date_at")->fetchAll(PDO::FETCH_COLUMN);
    check($retainedIds === array_values(array_filter($ids, fn($id) => $id !== $missing->id)), 'Concurrent generation preserves retained IDs');
}
$routine->setAlarm(2, 5, 'UTC');
check(Event::findByIdAndUser($events[0]->id, 2)->alarm === 5, 'Member has own alarm');
$pastId = Event::create(1, 'Past session', '2000-01-02 10:00:00')->id;
$pdo->exec("UPDATE event SET routine_id=".$routine->id.",routine_date='2000-01-02' WHERE id=".$pastId);
EventUser::apply($pastId, 1, 7);
$first = $events[0];
$second = $events[1];
$first->update('Personal exception', $first->date_at);
EventUser::apply($first->id, 1, null);
$second->delete();
Routine::findByIdAndUser($routine->id, 2)->update(array_replace($data, ['title' => 'Changed', 'time' => '22:00']), 'UTC');
check(Event::findByIdAndUser($first->id, 1)->title === 'Personal exception', 'Individual title survives series update');
check(Event::findByIdAndUser($first->id, 1)->alarm === null, 'Explicit mute overrides inherited alarm');
check($pdo->query('SELECT COUNT(*) FROM event WHERE id = '.$second->id)->fetchColumn() === 0, 'Deleted session does not reappear');
$routine->setAlarm(1, 30, 'UTC');
check(Event::findByIdAndUser($first->id, 1)->alarm === null, 'Routine alarm preserves explicit mute');
$routine->update(array_replace($data, ['active' => false]), 'UTC');
check(count(Event::findWithFilters(1, [])) === 1, 'Pause removes future but preserves past');
check(Event::findByIdAndUser($pastId, 1)->title === 'Past session', 'Past title remains unchanged');
check(Event::findByIdAndUser($pastId, 1)->alarm === 7, 'Past alarm unchanged by routine alarm');
$routine->update($data, 'UTC');
$restored = $pdo->query("SELECT id FROM event WHERE title = 'Personal exception'")->fetchColumn();
check((bool)$restored, 'Exception restored after pause');
check(Event::findByIdAndUser((int)$restored, 1)->alarm === null, 'Mute restored after pause');
check($pdo->query("SELECT COUNT(*) FROM event WHERE routine_date = '".$second->routine_date."'")->fetchColumn() === 0, 'Cancellation survives pause');
$pdo->exec("INSERT INTO event (calendar_id,title,date_at,routine_id,routine_date) VALUES (1,'Past','2000-01-01 10:00:00',".$routine->id.",'2000-01-01')");
$routine->delete('UTC');
check($pdo->query("SELECT routine_id FROM event WHERE title='Past'")->fetchColumn() === null, 'Delete detaches history');
check(count(Event::findWithFilters(1, [])) === 2, 'Delete preserves only history');
check(Event::findByIdAndUser($pastId, 1)->alarm === 7, 'Historical alarm survives deletion');
$next = $today->modify('+1 day')->format('Y-m-d');
$bounded = Routine::create(1, 2, array_replace($data, ['days' => [1,2,3,4,5,6,7], 'start_date' => $next, 'end_date' => $next]), 'UTC');
$boundedEvents = array_values(array_filter(Event::findWithFilters(2, []), fn($event) => $event->routine_id === $bounded->id));
check(count($boundedEvents) === 1 && $boundedEvents[0]->routine_date === $next, 'Start and end dates inclusive');
Routine::materializeForUser(2, 'Europe/Madrid');
check(Event::findByIdAndUser($boundedEvents[0]->id, 2)->date_at === $next.' 23:59:00', 'Changing timezone preserves floating local hour');
$wide = Routine::create(1, 1, array_replace($data, ['days' => [1,2,3,4,5,6,7], 'end_date' => null]), 'UTC');
$wideEvents = array_values(array_filter(Event::findWithFilters(1, []), fn($event) => $event->routine_id === $wide->id));
check(count($wideEvents) === 90, 'Generation uses 90-day horizon');
$far = $wideEvents[1];
$farDate = $today->modify('+200 days')->format('Y-m-d').' 12:00:00';
$far->update('Far exception', $farDate);
$wide->update(array_replace($data, ['days' => [1,2,3,4,5,6,7], 'end_date' => null]), 'UTC');
check(Event::findByIdAndUser($far->id, 1)->date_at === $farDate, 'Future exceptions outside generation horizon remain');
echo "Routine behavioral checks passed\n";
