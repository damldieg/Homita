<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Routine;

class RoutineAlarm extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        $this->routine()->setAlarm($this->user->id, Routine::validateAlarm($this->getInput('alarm')), $this->getInputTimezone());
        return $this->routine();
    }
}
