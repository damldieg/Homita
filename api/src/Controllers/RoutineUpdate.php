<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Person;

class RoutineUpdate extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        $routine = $this->routine();
        $personIds = Person::validateIds($this->getInput('person_ids'), $this->user->id);
        $routine->update($this->input, $this->getInputTimezone());
        if ($personIds !== null) Person::syncRoutine($routine->id, $personIds);
        return $this->routine();
    }
}
