<?php declare(strict_types=1);

namespace App\Controllers;

class RoutineDelete extends RoutineControllerAbstract
{
    protected function run(): mixed
    {
        $this->routine()->delete($this->getInputTimezone());
        return ['success' => true];
    }
}
