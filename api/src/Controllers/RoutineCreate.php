<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Person;
use App\Models\Routine;
use InvalidArgumentException;

class RoutineCreate extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        $calendarId = $this->getInputInt('calendar_id');
        if (!$calendarId) throw new InvalidArgumentException('Calendar ID is required');
        $personIds = Person::validateIds($this->getInput('person_ids'), $this->user->id);
        $routine = Routine::create($calendarId, $this->user->id, $this->input, $this->getInputTimezone());
        if ($personIds === null) return $routine;
        Person::syncRoutine($routine->id, $personIds);
        return Routine::findByIdAndUser($routine->id, $this->user->id);
    }
}
