<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Event;
use App\Models\Routine;

class EventDelete extends ControllerAbstract
{
    public function handle(): void
    {
        Routine::materializeForUser($this->user->id, $this->getInputTimezone());

        $id = $this->getInputInt('id');

        if (empty($id)) {
            $this->response(['error' => 'Event ID is required'], 400);
        }

        Event::findByIdAndUser($id, $this->user->id)->delete();

        $this->response(['success' => true], 200);
    }
}
