<?php declare(strict_types=1);

namespace App\Utils;

use RuntimeException;

class Config
{
    private static array $data = [];

    public static function key(string $scope, string $key): mixed
    {
        $config = self::get($scope);

        if (array_key_exists($key, $config) === false) {
            throw new RuntimeException(sprintf('Invalid config key %s', $key));
        }

        return $config[$key];
    }

    public static function get(string $scope): array
    {
        return self::$data[$scope] ??= self::load($scope);
    }

    private static function load(string $scope): array
    {
        $config = self::file($scope);

        if (is_file($config) === false) {
            throw new RuntimeException(sprintf('Invalid config scope %s', $scope));
        }

        $config = json_decode(file_get_contents($config), true);

        if (is_file($local = self::file($scope.'.local'))) {
            $config = json_decode(file_get_contents($local), true) + $config;
        }

        return $config;
    }

    private static function file(string $scope): string
    {
        return dirname(dirname(__DIR__)).'/config/'.$scope.'.json';
    }
}
