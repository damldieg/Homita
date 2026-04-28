<?php declare(strict_types=1);

namespace App\Utils;

use RuntimeException;

class Token
{
    private const CIPHER = 'aes-256-cbc';

    public static function generate(): string
    {
        return bin2hex(random_bytes(32));
    }

    public static function encrypt(string $plain): string
    {
        $cipher = openssl_encrypt($plain, self::CIPHER, self::key(), OPENSSL_RAW_DATA, self::iv());

        if ($cipher === false) {
            throw new RuntimeException('Token encryption failed');
        }

        return bin2hex($cipher);
    }

    public static function decrypt(string $encoded): string
    {
        $plain = openssl_decrypt(hex2bin($encoded), self::CIPHER, self::key(), OPENSSL_RAW_DATA, self::iv());

        if ($plain === false) {
            throw new RuntimeException('Token decryption failed');
        }

        return $plain;
    }

    private static function key(): string
    {
        return hash('sha256', self::secret(), true);
    }

    private static function iv(): string
    {
        return substr(hash('sha256', self::secret().':iv', true), 0, 16);
    }

    private static function secret(): string
    {
        return Config::key('private', 'token_secret');
    }
}
