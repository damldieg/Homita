<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Calendar;

class CalendarIndex extends ControllerAbstract
{
    public function handle(): void
    {
        $this->response(Calendar::findByUser($this->user->id), 200);
    }
}
