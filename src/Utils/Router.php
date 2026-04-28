<?php declare(strict_types=1);

namespace App\Utils;

use RuntimeException;
use Throwable;
use App\Utils\Error;

class Router
{
    private array $routes = [];

    public function get(string $path, callable $handler): void
    {
        $this->addRoute('GET', $path, $handler);
    }

    public function post(string $path, callable $handler): void
    {
        $this->addRoute('POST', $path, $handler);
    }

    public function put(string $path, callable $handler): void
    {
        $this->addRoute('PUT', $path, $handler);
    }

    public function patch(string $path, callable $handler): void
    {
        $this->addRoute('PATCH', $path, $handler);
    }

    public function delete(string $path, callable $handler): void
    {
        $this->addRoute('DELETE', $path, $handler);
    }

    private function addRoute(string $method, string $path, callable $handler): void
    {
        $this->routes[] = [
            'method' => $method,
            'pattern' => '#^'.preg_replace('/\{([a-zA-Z0-9_]+)\}/', '(?P<$1>[a-zA-Z0-9_-]+)', $path).'$#',
            'handler' => $handler,
        ];
    }

    public function dispatch(string $method, string $uri): void
    {
        $path = parse_url($uri)['path'] ?? '/';

        foreach ($this->routes as $route) {
            if (($route['method'] !== $method) || (preg_match($route['pattern'], $path, $matches) === 0)) {
                continue;
            }

            try {
                call_user_func($route['handler'], array_filter($matches, 'is_string', ARRAY_FILTER_USE_KEY));
            } catch (Throwable $e) {
                $this->error($e);
            }

            return;
        }

        $this->sendResponse(['error' => 'Not Found'], 404);
    }

    protected function sendResponse(array $data, int $statusCode = 200): void
    {
        http_response_code($statusCode);

        header('Content-Type: application/json');

        die(json_encode($data, JSON_THROW_ON_ERROR));
    }

    protected function error(Throwable $e): void
    {
        Error::report($e);

        $this->sendResponse(['error' => $e->getMessage()], 500);
    }
}
