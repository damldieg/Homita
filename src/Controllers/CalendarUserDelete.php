<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\CalendarUser;

class CalendarUserDelete extends ControllerAbstract
{
    public function handle(): void
    {
        $calendarId = $this->getInputInt('calendar_id');
        $userId = $this->getInputInt('user_id');

        if ($calendarId === 0 || $userId === 0) {
            $this->response(['error' => 'calendar_id and user_id are required'], 400);
        }

        CalendarUser::checkRole($calendarId, $this->user->id);

        if ($this->user->id === $userId) {
            $this->response(['error' => 'Owner cannot be removed'], 400);
        }

        CalendarUser::removeUser($calendarId, $userId);

        $this->response(['status' => 'ok']);
    }
}
