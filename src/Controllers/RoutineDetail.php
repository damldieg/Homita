<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Routine;

class RoutineDetail extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        $routine = $this->routine();
        Routine::materializeForUser($this->user->id, $this->getInputTimezone());
        return $routine;
    }
}
