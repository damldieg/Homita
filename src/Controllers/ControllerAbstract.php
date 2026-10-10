<?php declare(strict_types=1);

namespace App\Controllers;

use Exception;
use App\Models\User as UserModel;
use App\Utils\Error;

abstract class ControllerAbstract
{
    protected array $input;
    protected UserModel $user;

    abstract public function handle(): void;

    public function __construct()
    {
        $this->setInput();
    }

    protected function setInput(): self
    {
        $raw = file_get_contents('php://input');

        if (json_validate($raw)) {
            $input = json_decode($raw, true);
        } else {
            $input = [];
        }

        $this->input = $input + $_GET;

        return $this;
    }

    protected function getInput(string $key, mixed $default = null): mixed
    {
        return array_key_exists($key, $this->input) ? $this->input[$key] : $default;
    }

    protected function getInputString(string $key, mixed $default = null): ?string
    {
        return is_string($value = $this->getInput($key)) ? $value : $default;
    }

    protected function getInputInt(string $key, mixed $default = null): ?int
    {
        $value = $this->getInput($key);

        if (is_integer($value)) {
            return $value;
        }

        if (is_string($value) && preg_match('/^[0-9]+$/', $value)) {
            return intval($value);
        }

        return $default;
    }

    protected function getInputDateHour(string $key, mixed $default = null): ?string
    {
        $value = $this->getInputString($key);

        if (empty($value)) {
            return $default;
        }

        if (preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $value)) {
            return $value;
        }

        return $default;
    }

    protected function getInputBool(string $key, ?bool $default = null): ?bool
    {
        return filter_var($this->input[$key] ?? null, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) ?? $default;
    }

    protected function getInputEmail(string $key, mixed $default = null): ?string
    {
        return ($value = $this->getInputString($key)) ? trim(strval($value)) : $default;
    }

    protected function getInputTimezone(): string
    {
        $timezone = $this->getInput('timezone', 'UTC');
        if (!is_string($timezone)) throw new \InvalidArgumentException('Invalid timezone');
        \App\Models\Routine::cutoff($timezone);
        return $timezone;
    }

    public function setUser(UserModel $user): self
    {
        $this->user = $user;

        return $this;
    }

    public function middlewareAuth(): self
    {
        $header = getallheaders()['Authorization'] ?? '';

        if (preg_match('/Bearer\s+(.*)$/i', $header, $matches) === 0) {
            $this->response(['error' => 'Unauthorized'], 401);
        }

        return $this->setUser(UserModel::findByToken($matches[1]));
    }

    protected function response(mixed $data, int $status = 200)
    {
        if (($status !== 200) && is_array($data) && isset($data['error'])) {
            Error::report(new Exception($data['error']));
        }

        http_response_code($status);

        header('Content-Type: application/json');

        if (is_object($data) && method_exists($data, 'toArray')) {
            $data = $data->toArray();
        }

        if (is_array($data)) {
            $data = json_encode($data, JSON_THROW_ON_ERROR);
        }

        die(strval($data));
    }
}
