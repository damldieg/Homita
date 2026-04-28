<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Calendar;
use App\Models\CalendarUser;

class CalendarUpdate extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');
        $name = $this->getInputString('name');
        $color = $this->getInputString('color');
        $widget = $this->getInputBool('widget', true);

        if (empty($id) || empty($name) || empty($color)) {
            $this->response(['error' => 'Calendar ID, name and color are required'], 400);
        }

        $role = CalendarUser::check($id, $this->user->id);

        if ($role->role !== 'owner') {
            $this->response(['error' => 'Only owner can update the calendar'], 403);
        }

        CalendarUser::setWidget($id, $this->user->id, $widget);

        $this->response(Calendar::findById($id)->update($name, $color), 200);
    }
}
