<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Event;
use App\Models\EventUser;

class EventUpdate extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');
        $title = $this->getInputString('title');
        $dateAt = $this->getInputDateHour('date_at');
        $alarm = $this->getInputInt('alarm');

        if (empty($id) || empty($title) || empty($dateAt)) {
            $this->response(['error' => 'Event ID, title, and date_at are required'], 400);
        }

        Event::findByIdAndUser($id, $this->user->id)->update($title, $dateAt);

        EventUser::apply($id, $this->user->id, $alarm);

        $this->response(Event::findByIdAndUser($id, $this->user->id), 200);
    }
}
