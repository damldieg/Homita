<?php declare(strict_types=1);

namespace App\Models;

use App\Utils\Logger;
use App\Utils\Token;

class User extends ModelAbstract
{
    public int $id;
    public string $name;
    public string $email;
    public string $password;
    public string $token;
    public string $created_at;
    public string $updated_at;

    private bool $tokenExposed = false;

    public static function create(string $name, string $email, #[\SensitiveParameter] string $password): self
    {
        $plain = self::generateToken();

        $id = self::database()->insert(self::createSql(), [
            'name' => $name,
            'email' => $email,
            'password' => self::password($password),
            'token' => Token::encrypt($plain),
        ]);

        return self::findById($id)->exposeToken($plain);
    }

    private static function createSql(): string
    {
        return <<<'SQL'
            INSERT INTO `user` (`name`, `email`, `password`, `token`)
            VALUES (:name, :email, :password, :token)
        SQL;
    }

    public function exposeStoredToken(): self
    {
        return $this->exposeToken(Token::decrypt($this->attributes['token']));
    }

    private function exposeToken(string $plain): self
    {
        $this->token = $plain;
        $this->attributes['token'] = $plain;
        $this->tokenExposed = true;

        return $this;
    }

    private static function generateToken(): string
    {
        while (true) {
            $plain = Token::generate();

            if (self::tokenExists($plain) === false) {
                return $plain;
            }
        }
    }

    private static function tokenExists(string $plain): bool
    {
        return boolval(self::database()->selectOne(self::tokenExistsSql(), [
            'token' => Token::encrypt($plain),
        ]));
    }

    private static function tokenExistsSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `user`
            WHERE `token` = :token
            LIMIT 1
        SQL;
    }

    private static function password(#[\SensitiveParameter] string $password): string
    {
        return password_hash($password, PASSWORD_DEFAULT);
    }

    public static function emailExists(string $email): bool
    {
        return boolval(self::database()->selectOne(self::emailExistsSql(), [
            'email' => $email,
        ]));
    }

    private static function emailExistsSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `user`
            WHERE `email` = :email
            LIMIT 1
        SQL;
    }

    public static function findById(int $id): self
    {
        return new self(self::database()->selectOneOrFail(self::findByIdSql(), [
            'id' => $id,
        ]));
    }

    private static function findByIdSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `user`
            WHERE `id` = :id
            LIMIT 1
        SQL;
    }

    public static function findByToken(string $plain): self
    {
        return new self(self::database()->selectOneOrFail(self::findByTokenSql(), [
            'token' => Token::encrypt($plain),
        ]));
    }

    private static function findByTokenSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `user`
            WHERE `token` = :token
            LIMIT 1
        SQL;
    }

    public static function findByEmail(string $email): self
    {
        return new self(self::database()->selectOneOrFail(self::findByEmailSql(), [
            'email' => $email,
        ]));
    }

    private static function findByEmailSql(): string
    {
        return <<<'SQL'
            SELECT *
            FROM `user`
            WHERE `email` = :email
            LIMIT 1
        SQL;
    }

    public function update(string $name, string $email, #[\SensitiveParameter] ?string $password = null): self
    {
        if ($password) {
            $this->updateWithPassword($name, $email, $password);
        } else {
            $this->updateWithoutPassword($name, $email);
        }

        return self::findById($this->id);
    }

    private function updateWithPassword(string $name, string $email, #[\SensitiveParameter] string $password): void
    {
        self::database()->execute(self::updateWithPasswordSql(), [
            'name' => $name,
            'email' => $email,
            'password' => self::password($password),
            'id' => $this->id,
        ]);
    }

    private static function updateWithPasswordSql(): string
    {
        return <<<'SQL'
            UPDATE `user`
            SET `name` = :name,
                `email` = :email,
                `password` = :password,
                `updated_at` = CURRENT_TIMESTAMP
            WHERE `id` = :id
        SQL;
    }

    private function updateWithoutPassword(string $name, string $email): void
    {
        self::database()->execute(self::updateWithoutPasswordSql(), [
            'name' => $name,
            'email' => $email,
            'id' => $this->id,
        ]);
    }

    private static function updateWithoutPasswordSql(): string
    {
        return <<<'SQL'
            UPDATE `user`
            SET `name` = :name,
                `email` = :email,
                `updated_at` = CURRENT_TIMESTAMP
            WHERE `id` = :id
        SQL;
    }

    public function toArray(): array
    {
        $data = parent::toArray();

        unset($data['password']);

        if ($this->tokenExposed === false) {
            unset($data['token']);
        }

        return $data;
    }
}
