<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Routine;
use InvalidArgumentException;

abstract class RoutineControllerAbstract extends ControllerAbstract
{
    protected function routine(): Routine
    {
        $id = $this->getInputInt('id');
        if (!$id) throw new InvalidArgumentException('Routine ID is required');
        return Routine::findByIdAndUser($id, $this->user->id);
    }

    final public function handle(): void
    {
        $this->response($this->run(), 200);
    }

    abstract protected function run(): mixed;
}
