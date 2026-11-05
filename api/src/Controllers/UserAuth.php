<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\User;

class UserAuth extends ControllerAbstract
{
    public function handle(): void
    {
        $email = $this->getInputEmail('email');
        $password = $this->getInputString('password');

        if (empty($email) || empty($password)) {
            $this->response(['error' => 'Email and password are required'], 400);
        }

        $user = User::findByEmail($email);

        if (password_verify($password, $user->password) === false) {
            $this->response(['error' => 'Invalid credentials'], 401);
        }

        $this->response($user->exposeStoredToken());
    }
}
