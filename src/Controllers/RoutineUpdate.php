<?php declare(strict_types=1);

namespace App\Controllers;

class RoutineUpdate extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        $routine = $this->routine();
        $routine->update($this->input, $this->getInputTimezone());
        return $this->routine();
    }
}
