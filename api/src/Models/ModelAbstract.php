<?php declare(strict_types=1);

namespace App\Models;

use BadMethodCallException;
use ReflectionClass;
use App\Utils\Database;

abstract class ModelAbstract
{
    protected static array $properties;

    protected static Database $database;

    public function __construct(protected array $attributes)
    {
        $this->attributes();
    }

    protected function attributes(): void
    {
        $this->propertiesCheck();

        foreach ($this->attributes as $key => $value) {
            $this->$key = $value;
        }
    }

    protected function propertiesCheck(): void
    {
        $properties = $this->properties();
        $keys = array_keys($this->attributes);

        if ($diff = array_diff($keys, $properties)) {
            throw new BadMethodCallException(sprintf('Invalid attributes %s on %s', implode(', ', $diff), $this::class));
        }
    }

    protected function properties(): array
    {
        return static::$properties[$this::class] ??= $this->propertiesMap();
    }

    protected function propertiesMap(): array
    {
        return array_values(array_filter(array_map(
            static fn ($value) => $value->isPublic() ? $value->getName() : null,
            new ReflectionClass($this)->getProperties()
        )));
    }

    public function __toString(): string
    {
        return json_encode($this->attributes, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }

    public function toArray(): array
    {
        return json_decode($this->__toString(), true);
    }

    protected static function database(): Database
    {
        return self::$database ??= new Database();
    }

    protected static function getFilter(array $filters, string $key, mixed $default = null): mixed
    {
        return array_key_exists($key, $filters) ? $filters[$key] : $default;
    }

    protected static function getFilterString(array $filters, string $key, mixed $default = null): ?string
    {
        return ($value = self::getFilter($filters, $key)) ? trim(strval($value)) : $default;
    }

    protected static function getFilterInt(array $filters, string $key, mixed $default = null): ?int
    {
        return ($value = self::getFilter($filters, $key)) ? intval($value) : $default;
    }

    protected static function getFilterTimestamp(array $filters, string $key, mixed $default = null): ?string
    {
        $value = self::getFilterString($filters, $key);

        if (empty($value)) {
            return $default;
        }

        if (preg_match('/^\d{10}$/', $value)) {
            return date('Y-m-d H:i:s', intval($value));
        }

        return $default;
    }

    protected static function getFilterBool(array $filters, string $key, ?bool $default = null): ?bool
    {
        if (isset($filters[$key]) === false) {
            return $default;
        }

        return filter_var($filters[$key], FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) ?? $default;
    }
}
