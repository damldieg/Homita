<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Event;
use App\Models\Routine;
use App\Models\EventUser;
use App\Models\Person;

class EventUpdate extends ControllerAbstract
{
    public function handle(): void
    {
        Routine::materializeForUser($this->user->id, $this->getInputTimezone());

        $id = $this->getInputInt('id');
        $title = $this->getInputString('title');
        $dateAt = $this->getInputDateHour('date_at');
        $alarm = $this->getInputInt('alarm');
        Routine::validateAlarm($alarm);
        $personIds = Person::validateIds($this->getInput('person_ids'), $this->user->id);

        if (empty($id) || empty($title) || empty($dateAt)) {
            $this->response(['error' => 'Event ID, title, and date_at are required'], 400);
        }

        Event::findByIdAndUser($id, $this->user->id)->update($title, $dateAt);

        EventUser::apply($id, $this->user->id, $alarm);

        if ($personIds !== null) {
            Person::syncEvent($id, $personIds);
        }

        $this->response(Event::findByIdAndUser($id, $this->user->id), 200);
    }
}
