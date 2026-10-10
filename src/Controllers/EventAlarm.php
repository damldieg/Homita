<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Event;
use App\Models\Routine;
use App\Models\EventUser;

class EventAlarm extends ControllerAbstract
{
    public function handle(): void
    {
        Routine::materializeForUser($this->user->id, $this->getInputTimezone());

        $eventId = $this->getInputInt('event_id');
        $alarm = $this->getInputInt('alarm');

        if (empty($eventId)) {
            $this->response(['error' => 'event_id is required'], 400);
        }

        Event::findByIdAndUser($eventId, $this->user->id);

        EventUser::apply($eventId, $this->user->id, $alarm);

        $this->response(Event::findByIdAndUser($eventId, $this->user->id), 200);
    }
}
