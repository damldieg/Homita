<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Event;

class EventIndex extends ControllerAbstract
{
    public function handle(): void
    {
        $this->response($this->list(), 200);
    }

    protected function list(): array
    {
        return Event::findWithFilters($this->user->id, array_replace($this->input, ['timezone' => $this->getInputTimezone()]));
    }
}
