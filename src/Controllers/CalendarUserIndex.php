<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\CalendarUser;

class CalendarUserIndex extends ControllerAbstract
{
    public function handle(): void
    {
        $calendarId = $this->getInputInt('calendar_id');

        if ($calendarId === 0) {
            $this->response(['error' => 'calendar_id is required'], 400);
        }

        CalendarUser::check($calendarId, $this->user->id);

        $this->response(CalendarUser::findUsersByCalendar($calendarId));
    }
}
