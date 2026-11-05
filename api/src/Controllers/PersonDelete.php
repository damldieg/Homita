<?php declare(strict_types=1);

namespace App\Controllers;

class PersonDelete extends PersonControllerAbstract
{
    protected function run(): mixed
    {
        $this->person()->delete();
        return ['success' => true];
    }
}
