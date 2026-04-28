<?php declare(strict_types=1);

namespace App\Utils;

use RuntimeException;

class GeminiClient
{
    private string $apiKey;
    private string $model = 'gemini-3.1-flash-lite-preview';
    private string $baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/';

    public function __construct()
    {
        $this->apiKey = Config::key('private', 'gemini_api_key');

        if (empty($this->apiKey)) {
            throw new RuntimeException('Gemini API key is not configured');
        }
    }

    public function parseEventText(string $text): array
    {
        return $this->request($this->systemPrompt(), $text, $this->eventSchema());
    }

    private function systemPrompt(): string
    {
        $now = date('Y-m-d H:i:s');
        $day = $this->dayOfWeek();

        return <<<PROMPT
        Eres un asistente que extrae eventos de calendario a partir de texto en cualquier idioma.
        Fecha y hora actual: {$now} ({$day}).
        Extrae el título del evento y la fecha/hora en formato YYYY-MM-DD HH:MM:SS.
        Si no se especifica hora, usa 00:00:00.
        Si la fecha es relativa (mañana, el viernes, etc.) resuélvela a partir de la fecha actual.
        PROMPT;
    }

    private function eventSchema(): array
    {
        return [
            'type' => 'object',
            'properties' => [
                'title' => [
                    'type' => 'string',
                    'description' => 'Título corto del evento',
                ],
                'date_at' => [
                    'type' => 'string',
                    'description' => 'Fecha y hora en formato YYYY-MM-DD HH:MM:SS',
                ],
            ],
            'required' => ['title', 'date_at'],
        ];
    }

    private function request(string $system, string $user, array $schema): array
    {
        return $this->parse($this->curl($this->url(), $this->headers(), $this->payload($system, $user, $schema)));
    }

    private function payload(string $system, string $user, array $schema): array
    {
        return [
            'systemInstruction' => [
                'parts' => [['text' => $system]],
            ],
            'contents' => [
                [
                    'role' => 'user',
                    'parts' => [['text' => $user]],
                ],
            ],
            'generationConfig' => [
                'responseMimeType' => 'application/json',
                'responseJsonSchema' => $schema,
            ],
        ];
    }

    private function url(): string
    {
        return $this->baseUrl.$this->model.':generateContent';
    }

    private function headers(): array
    {
        return [
            'Content-Type: application/json',
            'x-goog-api-key: '.$this->apiKey,
        ];
    }

    private function curl(string $url, array $headers, array $payload): string
    {
        $ch = curl_init($url);

        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

        if (($httpCode !== 200) || empty($response)) {
            throw new RuntimeException('Gemini API error (HTTP '.$httpCode.')');
        }

        return $response;
    }

    private function parse(string $response): array
    {
        $text = json_decode($response, true)['candidates'][0]['content']['parts'][0]['text'] ?? '';

        if (json_validate($text) === false) {
            throw new RuntimeException('Empty response from Gemini API');
        }

        return json_decode($text, true);
    }

    private function dayOfWeek(): string
    {
        return match (intval(date('N'))) {
            1 => 'lunes',
            2 => 'martes',
            3 => 'miércoles',
            4 => 'jueves',
            5 => 'viernes',
            6 => 'sábado',
            7 => 'domingo',
        };
    }
}
