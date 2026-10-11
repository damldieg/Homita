<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Person;
use InvalidArgumentException;

abstract class PersonControllerAbstract extends ControllerAbstract
{
    /** Solo el creador puede editar o borrar una persona. */
    protected function person(): Person
    {
        $id = $this->getInputInt('id');
        if (!$id) throw new InvalidArgumentException('Person ID is required');
        return Person::findByIdAndOwner($id, $this->user->id);
    }

    final public function handle(): void
    {
        $this->response($this->run(), 200);
    }

    abstract protected function run(): mixed;
}
