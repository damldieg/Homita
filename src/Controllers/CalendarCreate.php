<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Calendar;
use App\Models\CalendarUser;

class CalendarCreate extends ControllerAbstract
{
    public function handle(): void
    {
        $name = $this->getInputString('name');
        $color = $this->getInputString('color');
        $widget = $this->getInputBool('widget', true);

        if (empty($name)) {
            $this->response(['error' => 'Name is required'], 400);
        }

        $calendar = Calendar::create($name, $color);

        CalendarUser::create($calendar->id, $this->user->id, 'owner', $widget);

        $this->response($calendar, 201);
    }
}
