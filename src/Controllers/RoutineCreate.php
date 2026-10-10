<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Routine;
use InvalidArgumentException;

class RoutineCreate extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        $calendarId = $this->getInputInt('calendar_id');
        if (!$calendarId) throw new InvalidArgumentException('Calendar ID is required');
        return Routine::create($calendarId, $this->user->id, $this->input, $this->getInputTimezone());
    }
}
