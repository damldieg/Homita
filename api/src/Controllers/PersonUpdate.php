<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Person;

class PersonUpdate extends PersonControllerAbstract
{
    protected function run(): mixed
    {
        $person = $this->person();
        $person->update($this->input);
        return $this->present(Person::findByIdAndOwner($person->id, $this->user->id));
    }
}
