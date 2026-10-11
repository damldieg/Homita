<?php declare(strict_types=1);

require dirname(__DIR__).'/src/autoload.php';

use App\Models\Event;
use App\Models\Person;
use App\Models\Routine;
use App\Utils\Database;
use App\Utils\DatabaseLog;

function check(bool $condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

function ids(array $persons): array {
    return array_map(static fn($person) => is_array($person) ? $person['id'] : $person->id, $persons);
}

$file = tempnam(sys_get_temp_dir(), 'planify-person-');
register_shutdown_function(static fn() => unlink($file));
$pdo = new PDO('sqlite:'.$file, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC, PDO::ATTR_EMULATE_PREPARES => false]);
$pdo->exec('PRAGMA foreign_keys = ON');
new ReflectionProperty(Database::class, 'instance')->setValue(null, $pdo);
new ReflectionProperty(DatabaseLog::class, 'config')->setValue(null, ['enabled' => false]);
foreach (glob(dirname(__DIR__).'/migrations/*.sql') as $migration) $pdo->exec(file_get_contents($migration));
// 1 y 2 comparten calendario; 3 no comparte nada
$pdo->exec("INSERT INTO user (id,name,email,password,token) VALUES (1,'Owner','a@b','x','a'),(2,'Member','c@d','x','b'),(3,'Other','e@f','x','c'); INSERT INTO calendar (id,name,token) VALUES (1,'Home','h'),(2,'Private','p'); INSERT INTO calendar_user (calendar_id,user_id,role) VALUES (1,1,'owner'),(1,2,'viewer'),(2,3,'owner')");

foreach ([['name' => ''], ['name' => str_repeat('x', 51)], ['color' => 'red'], ['color' => '#12345']] as $invalid) {
    try { Person::validate(array_replace(['name' => 'Ana', 'color' => '#112233'], $invalid)); throw new RuntimeException('Invalid person accepted'); }
    catch (InvalidArgumentException) {}
}

$ana = Person::create(1, ['name' => ' Ana ', 'color' => '#aa0000']);
check($ana->name === 'Ana' && $ana->color === '#AA0000', 'Name trimmed and color normalized');
$bruno = Person::create(2, ['name' => 'Bruno', 'color' => '#00AA00']);
$carla = Person::create(3, ['name' => 'Carla', 'color' => '#0000AA']);

check(ids(Person::findVisibleForUser(1)) === [$ana->id, $bruno->id], 'Shared calendar members see each other persons');
check(ids(Person::findVisibleForUser(2)) === [$ana->id, $bruno->id], 'Visibility is symmetric');
check(ids(Person::findVisibleForUser(3)) === [$carla->id], 'Outsiders only see their own persons');

try { Person::findByIdAndOwner($ana->id, 2); throw new RuntimeException('Member edited another user person'); }
catch (Exception $error) { check($error->getMessage() === 'Not Found', 'Only the creator can edit'); }
Person::findByIdAndOwner($ana->id, 1)->update(['name' => 'Ana María', 'color' => '#AA0000']);
check(Person::findByIdAndOwner($ana->id, 1)->name === 'Ana María', 'Creator updates');

check(Person::validateIds(null, 1) === null, 'Omitted person_ids leaves assignment untouched');
check(Person::validateIds([$bruno->id, $ana->id, $ana->id], 1) === [$bruno->id, $ana->id], 'Duplicates removed');
foreach ([[$carla->id], ['1'], 'x', ['a' => 1]] as $invalid) {
    try { Person::validateIds($invalid, 1); throw new RuntimeException('Invalid person_ids accepted'); }
    catch (InvalidArgumentException) {}
}

$today = new DateTimeImmutable('today', new DateTimeZone('UTC'));
$event = Event::create(1, 'Dentist', $today->modify('+1 day')->format('Y-m-d').' 10:00:00');
$other = Event::create(1, 'Nobody', $today->modify('+1 day')->format('Y-m-d').' 11:00:00');
Person::syncEvent($event->id, [$ana->id, $bruno->id]);
check(ids(Event::findByIdAndUser($event->id, 2)->persons) === [$ana->id, $bruno->id], 'Event detail includes persons');
check(Event::findByIdAndUser($other->id, 1)->toArray()['persons'] === [], 'Events without persons return an empty list');
Person::syncEvent($event->id, [$bruno->id]);
check(ids(Event::findByIdAndUser($event->id, 1)->persons) === [$bruno->id], 'Sync replaces persons');

$routine = Routine::create(1, 1, ['title' => 'Swim', 'days' => [1,2,3,4,5,6,7], 'time' => '23:59', 'start_date' => $today->format('Y-m-d'), 'end_date' => $today->modify('+3 days')->format('Y-m-d'), 'active' => true], 'UTC');
Person::syncRoutine($routine->id, [$ana->id]);
check(ids(Routine::findByIdAndUser($routine->id, 2)->persons) === [$ana->id], 'Routine includes persons');
check(ids(Routine::findByUser(1, 'UTC')[0]->persons) === [$ana->id], 'Routine index includes persons');
$sessions = Event::findWithFilters(1, ['routine' => 'true']);
check($sessions !== [] && array_all($sessions, fn($session) => ids($session->persons) === [$ana->id]), 'Sessions inherit routine persons');
Person::syncRoutine($routine->id, [$ana->id, $bruno->id]);
check(ids(Event::findWithFilters(1, ['routine' => 'true'])[0]->persons) === [$ana->id, $bruno->id], 'Routine person changes reach sessions immediately');

$forAna = Event::findWithFilters(1, ['person_id' => (string)$ana->id]);
check(array_all($forAna, fn($found) => $found->routine_id === $routine->id) && count($forAna) === count($sessions), 'Person filter matches routine sessions');
check(array_map(fn($found) => $found->id, Event::findWithFilters(1, ['person_id' => (string)$bruno->id, 'routine' => 'false'])) === [$event->id], 'Person filter matches assigned events');

$past = Event::create(1, 'Past swim', '2000-01-01 10:00:00');
$pdo->exec("UPDATE event SET routine_id={$routine->id},routine_date='2000-01-01' WHERE id={$past->id}");
$routine->delete('UTC');
check(ids(Event::findByIdAndUser($past->id, 1)->persons) === [$ana->id, $bruno->id], 'Detached history keeps routine persons');

Person::findByIdAndOwner($bruno->id, 2)->delete();
check(Event::findByIdAndUser($event->id, 1)->persons === [], 'Deleting a person removes assignments');
check(ids(Person::findVisibleForUser(1)) === [$ana->id], 'Deleted person disappears');
echo "Person behavioral checks passed\n";
