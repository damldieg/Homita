<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Routine;

class RoutineIndex extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        return Routine::findByUser($this->user->id, $this->getInputTimezone());
    }
}
