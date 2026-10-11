<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Person;

class PersonIndex extends PersonControllerAbstract
{
    protected function run(): mixed
    {
        return array_map(static fn(Person $person) => $person->toArray(), Person::findVisibleForUser($this->user->id));
    }
}
