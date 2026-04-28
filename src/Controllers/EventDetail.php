<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Event;

class EventDetail extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');

        if (empty($id)) {
            $this->response(['error' => 'Event ID is required'], 400);
        }

        $this->response(Event::findByIdAndUser($id, $this->user->id), 200);
    }
}
