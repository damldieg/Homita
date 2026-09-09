<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\User;
use App\Models\CalendarUser;

class CalendarUserCreate extends ControllerAbstract
{
    public function handle(): void
    {
        $calendarId = $this->getInputInt('calendar_id');
        $email = $this->getInputEmail('email');

        if (empty($calendarId) || empty($email)) {
            $this->response(['error' => 'Calendar ID and email are required'], 400);
        }

        CalendarUser::check($calendarId, $this->user->id);

        $target = User::findByEmail($email);

        if (CalendarUser::exists($calendarId, $target->id) === false) {
            CalendarUser::create($calendarId, $target->id, 'viewer');
        }

        $this->response($target, 200);
    }
}
