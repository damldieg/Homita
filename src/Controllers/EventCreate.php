<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Event;
use App\Models\EventUser;
use App\Models\Person;
use App\Models\Routine;
use App\Models\CalendarUser;
use App\Utils\GeminiClient;

class EventCreate extends ControllerAbstract
{
    public function handle(): void
    {
        $calendarId = $this->getInputInt('calendar_id');
        $text = $this->getInputString('text');
        $title = $this->getInputString('title');
        $dateAt = $this->getInputDateHour('date_at');
        $alarm = $this->getInputInt('alarm');
        Routine::validateAlarm($alarm);
        $personIds = Person::validateIds($this->getInput('person_ids'), $this->user->id);

        if (empty($calendarId)) {
            $this->response(['error' => 'Calendar ID is required'], 400);
        }

        if (empty($text) && (empty($title) || empty($dateAt))) {
            $this->response(['error' => 'Title and date_at are required if text is not provided'], 400);
        }

        CalendarUser::check($calendarId, $this->user->id);

        if ($title && $dateAt) {
            $event = $this->createByTitleAndDate($calendarId, $title, $dateAt);
        } else {
            $event = $this->createByText($calendarId, $text);
        }

        EventUser::apply($event->id, $this->user->id, $alarm);

        if ($personIds !== null) {
            Person::syncEvent($event->id, $personIds);
        }

        $this->response(Event::findByIdAndUser($event->id, $this->user->id), 200);
    }

    private function createByTitleAndDate(int $calendarId, string $title, string $dateAt): Event
    {
        return Event::create($calendarId, $title, $dateAt);
    }

    private function createByText(int $calendarId, string $text): Event
    {
        $data = new GeminiClient()->parseEventText($text);

        if (empty($data['title']) || empty($data['date_at'])) {
            $this->response(['error' => 'Title and date_at are required if text is not provided'], 400);
        }

        return Event::create($calendarId, $data['title'], $data['date_at']);
    }
}
