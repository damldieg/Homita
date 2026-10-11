<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Person;

class PersonCreate extends PersonControllerAbstract
{
    protected function run(): mixed
    {
        return Person::create($this->user->id, $this->input);
    }
}
