<?php declare(strict_types=1);

namespace App\Models;

use App\Utils\Database;
use DateTimeImmutable;
use DateTimeZone;
use InvalidArgumentException;

class Routine extends ModelAbstract
{
    public int $id;
    public int $calendar_id;
    public ?string $calendar_name = null;
    public ?string $calendar_color = null;
    public string $title;
    public string $frequency;
    public int $interval;
    public array $days;
    public string $time;
    public string $start_date;
    public ?string $end_date;
    public bool $active;
    public string $available_from;
    public ?int $alarm = null;
    public array $persons = [];
    public string $created_at;
    public string $updated_at;

    public function __construct(array $attributes)
    {
        $attributes['days'] = json_decode($attributes['days'], true, 512, JSON_THROW_ON_ERROR);
        $attributes['active'] = (bool)$attributes['active'];
        parent::__construct($attributes);
    }

    public static function cutoff(string $timezone = 'UTC'): string
    {
        if (!in_array($timezone, DateTimeZone::listIdentifiers(DateTimeZone::ALL_WITH_BC), true)) throw new InvalidArgumentException('Invalid timezone');
        try { $zone = new DateTimeZone($timezone); }
        catch (\Exception) { throw new InvalidArgumentException('Invalid timezone'); }
        return new DateTimeImmutable('now', $zone)->format('Y-m-d H:i:s');
    }

    private const FREQUENCIES = ['daily', 'weekly', 'monthly'];

    /** Sin `frequency` o `interval` (clientes anteriores), se mantienen los de [$current] o semanal cada 1. */
    public static function validate(array $data, ?array $current = null): array
    {
        if (!is_string($data['title'] ?? null)) throw new InvalidArgumentException('Title is required');
        $title = trim($data['title']);
        $frequency = $data['frequency'] ?? $current['frequency'] ?? 'weekly';
        $interval = $data['interval'] ?? $current['interval'] ?? 1;
        if (!in_array($frequency, self::FREQUENCIES, true)) throw new InvalidArgumentException('Frequency must be daily, weekly or monthly');
        if (!is_int($interval) || $interval < 1 || $interval > 99) throw new InvalidArgumentException('Interval must be 1 to 99');
        // Solo la semanal usa días de la semana: la diaria cuenta desde el inicio y la mensual repite su día del mes
        $days = $frequency === 'weekly' ? $data['days'] ?? null : [];
        $time = $data['time'] ?? null;
        $start = $data['start_date'] ?? null;
        $end = $data['end_date'] ?? null;
        if ($title === '' || !is_array($days) || ($frequency === 'weekly' && $days === []) || !array_is_list($days)) {
            throw new InvalidArgumentException('Title and selected days are required');
        }
        foreach ($days as $day) {
            if (!is_int($day) || $day < 1 || $day > 7) throw new InvalidArgumentException('Days must be ISO weekdays 1 to 7');
        }
        $days = array_values(array_unique($days));
        sort($days);
        if (!is_string($time) || !preg_match('/^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/', $time)) throw new InvalidArgumentException('Invalid time');
        foreach ([$start, $end] as $date) {
            if ($date === null) continue;
            if (!is_string($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) throw new InvalidArgumentException('Invalid date');
            $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $date);
            if (!$parsed || $parsed->format('Y-m-d') !== $date) throw new InvalidArgumentException('Invalid date');
        }
        if ($start === null || ($end !== null && $end < $start)) throw new InvalidArgumentException('Invalid date range');
        if (!is_bool($data['active'] ?? null)) throw new InvalidArgumentException('Active must be boolean');
        return ['title' => $title, 'frequency' => $frequency, 'interval' => $interval, 'days' => json_encode($days), 'time' => $time, 'start_date' => $start, 'end_date' => $end, 'active' => (int)$data['active']];
    }

    public static function validateAlarm(mixed $alarm): ?int
    {
        if ($alarm !== null && (!is_int($alarm) || $alarm < 0)) throw new InvalidArgumentException('Alarm must be nonnegative minutes or null');
        return $alarm;
    }

    public static function create(int $calendarId, int $userId, array $data, string $timezone = 'UTC'): self
    {
        $values = self::validate($data);
        $alarm = self::validateAlarm($data['alarm'] ?? null);
        $now = self::cutoff($timezone);
        return Database::transaction(function () use ($calendarId, $userId, $values, $alarm, $now) {
            CalendarUser::check($calendarId, $userId);
            $id = self::database()->insert('INSERT INTO routine (calendar_id,title,frequency,interval,days,time,start_date,end_date,active,available_from) VALUES (:calendar_id,:title,:frequency,:interval,:days,:time,:start_date,:end_date,:active,:available_from)', $values + ['calendar_id' => $calendarId, 'available_from' => $now]);
            self::database()->execute('INSERT INTO routine_user (routine_id,user_id,alarm) VALUES (:routine_id,:user_id,:alarm)', ['routine_id' => $id, 'user_id' => $userId, 'alarm' => $alarm]);
            $routine = self::findByIdAndUser($id, $userId);
            $routine->materialize($now);
            return $routine;
        }, true);
    }

    private const SELECT = 'SELECT r.*, c.name AS calendar_name, c.color AS calendar_color, ru.alarm FROM routine r INNER JOIN calendar c ON c.id=r.calendar_id LEFT JOIN routine_user ru ON ru.routine_id=r.id AND ru.user_id=:user_id WHERE EXISTS (SELECT 1 FROM calendar_user cu WHERE cu.calendar_id=r.calendar_id AND cu.user_id=:user_id)';

    public static function findByIdAndUser(int $id, int $userId): self
    {
        return self::withPersons([new self(self::database()->selectOneOrFail(self::SELECT.' AND r.id=:id', ['id' => $id, 'user_id' => $userId]))])[0];
    }

    /** Añade `persons` a cada rutina con una sola consulta. */
    public static function withPersons(array $routines): array
    {
        $persons = Person::byRoutine(array_map(static fn(self $routine) => $routine->id, $routines));
        foreach ($routines as $routine) $routine->attributes['persons'] = $routine->persons = $persons[$routine->id] ?? [];
        return $routines;
    }

    public static function findByUser(int $userId, string $timezone = 'UTC'): array
    {
        self::materializeForUser($userId, $timezone);
        return self::withPersons(array_map(static fn($row) => new self($row), self::database()->select(self::SELECT.' ORDER BY r.title, r.id', ['user_id' => $userId])));
    }

    public static function materializeForUser(int $userId, string $timezone = 'UTC'): void
    {
        $now = self::cutoff($timezone);
        Database::transaction(function () use ($userId, $now) {
            foreach (self::database()->select(self::SELECT.' AND r.active=1', ['user_id' => $userId]) as $row) new self($row)->materialize($now);
        }, true);
    }

    public function update(array $data, string $timezone = 'UTC'): void
    {
        $values = self::validate($data, ['frequency' => $this->frequency, 'interval' => $this->interval]);
        $now = self::cutoff($timezone);
        Database::transaction(function () use ($values, $now) {
            $current = self::database()->selectOneOrFail('SELECT * FROM routine WHERE id=:id', ['id' => $this->id]);
            $available = !$current['active'] && $values['active'] ? $now : $current['available_from'];
            self::database()->execute('UPDATE routine SET title=:title,frequency=:frequency,interval=:interval,days=:days,time=:time,start_date=:start_date,end_date=:end_date,active=:active,available_from=:available_from,updated_at=CURRENT_TIMESTAMP WHERE id=:id', $values + ['id' => $this->id, 'available_from' => $available]);
            $row = array_replace($current, $values, ['available_from' => $available]);
            new self($row)->materialize($now, true);
        }, true);
    }

    private function occurrences(string $now): array
    {
        if (!$this->active) return [];
        $from = max(substr($now, 0, 10), $this->start_date, substr($this->available_from, 0, 10));
        $last = new DateTimeImmutable(substr($now, 0, 10))->modify('+89 days')->format('Y-m-d');
        if ($this->end_date !== null) $last = min($last, $this->end_date);
        $dates = [];
        for ($day = new DateTimeImmutable($from); $day->format('Y-m-d') <= $last; $day = $day->modify('+1 day')) {
            $date = $day->format('Y-m-d');
            $dateAt = $date.' '.$this->time.':00';
            if ($this->matches($day) && $dateAt >= max($now, $this->available_from)) $dates[$date] = ['title' => $this->title, 'date_at' => $dateAt];
        }
        foreach (self::database()->select('SELECT * FROM routine_exception WHERE routine_id=:id', ['id' => $this->id]) as $exception) {
            $date = $exception['routine_date'];
            if ($exception['cancelled']) unset($dates[$date]);
            elseif ($exception['date_at'] >= max($now, $this->available_from)) $dates[$date] = ['title' => $exception['title'], 'date_at' => $exception['date_at']];
        }
        return $dates;
    }

    /** Si toca sesión ese día, contando cada [interval] días, semanas o meses desde el inicio. */
    private function matches(DateTimeImmutable $day): bool
    {
        $start = new DateTimeImmutable($this->start_date);
        return match ($this->frequency) {
            'daily' => $start->diff($day)->days % $this->interval === 0,
            // Semanas de lunes a domingo: la del inicio es la primera
            'weekly' => in_array((int)$day->format('N'), $this->days, true)
                && intdiv($start->modify('monday this week')->diff($day->modify('monday this week'))->days, 7) % $this->interval === 0,
            // El día del mes del inicio o, en los meses que no lo tienen (31 en abril), el último
            'monthly' => ((int)$day->format('Y') * 12 + (int)$day->format('n') - (int)$start->format('Y') * 12 - (int)$start->format('n')) % $this->interval === 0
                && (int)$day->format('j') === min((int)$start->format('j'), (int)$day->format('t')),
        };
    }

    private function materialize(string $now, bool $reconcile = false): void
    {
        $dates = $this->occurrences($now);
        $existing = self::database()->select('SELECT id,routine_date,date_at FROM event WHERE routine_id=:id', ['id' => $this->id]);
        foreach ($existing as $event) {
            $date = $event['routine_date'];
            if ($event['date_at'] < $now) { unset($dates[$date]); continue; }
            if ($reconcile && !isset($dates[$date])) self::database()->execute('DELETE FROM event WHERE id=:id', ['id' => $event['id']]);
            elseif ($reconcile && isset($dates[$date])) self::database()->execute('UPDATE event SET title=:title,date_at=:date_at,updated_at=CURRENT_TIMESTAMP WHERE id=:id', $dates[$date] + ['id' => $event['id']]);
            unset($dates[$date]);
        }
        foreach ($dates as $date => $values) {
            self::database()->execute('INSERT INTO event (calendar_id,title,date_at,routine_id,routine_date) VALUES (:calendar_id,:title,:date_at,:routine_id,:routine_date) ON CONFLICT(routine_id,routine_date) DO NOTHING', $values + ['calendar_id' => $this->calendar_id, 'routine_id' => $this->id, 'routine_date' => $date]);
        }
        $this->syncAlarms($now);
    }

    private function syncAlarms(string $now): void
    {
        self::database()->execute('INSERT INTO event_user (event_id,user_id,alarm) SELECT e.id,cu.user_id,CASE WHEN rea.user_id IS NOT NULL THEN rea.alarm ELSE ru.alarm END FROM event e INNER JOIN calendar_user cu ON cu.calendar_id=e.calendar_id LEFT JOIN routine_user ru ON ru.routine_id=e.routine_id AND ru.user_id=cu.user_id LEFT JOIN routine_event_alarm rea ON rea.routine_id=e.routine_id AND rea.routine_date=e.routine_date AND rea.user_id=cu.user_id WHERE e.routine_id=:id AND e.date_at>=:now GROUP BY e.id,cu.user_id ON CONFLICT(event_id,user_id) DO UPDATE SET alarm=excluded.alarm,updated_at=CURRENT_TIMESTAMP WHERE event_user.alarm IS NOT excluded.alarm', ['id' => $this->id, 'now' => $now]);
    }

    public function setAlarm(int $userId, ?int $alarm, string $timezone = 'UTC'): void
    {
        self::validateAlarm($alarm);
        $now = self::cutoff($timezone);
        Database::transaction(function () use ($userId, $alarm, $now) {
            self::findByIdAndUser($this->id, $userId);
            self::database()->execute('INSERT INTO routine_user (routine_id,user_id,alarm) VALUES (:id,:user_id,:alarm) ON CONFLICT(routine_id,user_id) DO UPDATE SET alarm=excluded.alarm', ['id' => $this->id, 'user_id' => $userId, 'alarm' => $alarm]);
            $this->syncAlarms($now);
        }, true);
    }

    public function delete(string $timezone = 'UTC'): void
    {
        $now = self::cutoff($timezone);
        Database::transaction(function () use ($now) {
            self::database()->execute('DELETE FROM event WHERE routine_id=:id AND date_at>=:now', ['id' => $this->id, 'now' => $now]);
            // El historial desvinculado conserva las personas que heredaba de la rutina
            self::database()->execute('INSERT OR IGNORE INTO event_person (event_id,person_id) SELECT e.id,rp.person_id FROM event e INNER JOIN routine_person rp ON rp.routine_id=e.routine_id WHERE e.routine_id=:id', ['id' => $this->id]);
            self::database()->execute('UPDATE event SET routine_id=NULL,routine_date=NULL WHERE routine_id=:id', ['id' => $this->id]);
            self::database()->execute('DELETE FROM routine WHERE id=:id', ['id' => $this->id]);
        }, true);
    }

    public static function saveException(Event $event, ?string $title, ?string $dateAt, bool $cancelled): void
    {
        self::database()->execute('INSERT INTO routine_exception (routine_id,routine_date,title,date_at,cancelled) VALUES (:id,:date,:title,:date_at,:cancelled) ON CONFLICT(routine_id,routine_date) DO UPDATE SET title=excluded.title,date_at=excluded.date_at,cancelled=excluded.cancelled', ['id' => $event->routine_id, 'date' => $event->routine_date, 'title' => $title, 'date_at' => $dateAt, 'cancelled' => (int)$cancelled]);
    }
}
