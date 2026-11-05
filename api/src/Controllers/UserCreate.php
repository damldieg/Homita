<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\User;
use App\Utils\Config;

class UserCreate extends ControllerAbstract
{
    public function handle(): void
    {
        if (Config::key('public', 'allow_registration') === false) {
            $this->response(['error' => 'Not Allowed'], 403);
        }

        $name = $this->getInputString('name');
        $email = $this->getInputEmail('email');
        $password = $this->getInputString('password');

        if (empty($name) || empty($email) || empty($password)) {
            $this->response(['error' => 'Name, email and password are required'], 400);
        }

        if (mb_strlen($name) < 3 || mb_strlen($name) > 50) {
            $this->response(['error' => 'Name must be between 3 and 50 characters'], 400);
        }

        if (mb_strlen($password) < 8) {
            $this->response(['error' => 'Password must be at least 8 characters'], 400);
        }

        if (User::emailExists($email)) {
            $this->response(['error' => 'Email already exists'], 400);
        }

        $this->response(User::create($name, $email, $password), 201);
    }
}
