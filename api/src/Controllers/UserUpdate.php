<?php declare(strict_types=1);

namespace App\Controllers;

class UserUpdate extends ControllerAbstract
{
    public function handle(): void
    {
        $name = $this->getInputString('name', $this->user->name);
        $email = $this->getInputEmail('email', $this->user->email);
        $password = $this->getInputString('password');

        if (empty($name) || empty($email)) {
            $this->response(['error' => 'Name and email cannot be empty'], 400);
        }

        if (mb_strlen($name) < 3 || mb_strlen($name) > 50) {
            $this->response(['error' => 'Name must be between 3 and 50 characters'], 400);
        }

        if ($password && (mb_strlen($password) < 8)) {
            $this->response(['error' => 'Password must be at least 8 characters'], 400);
        }

        $this->response($this->user->update($name, $email, $password), 200);
    }
}
