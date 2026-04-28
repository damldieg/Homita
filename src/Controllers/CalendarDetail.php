<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Calendar;
use App\Models\CalendarUser;

class CalendarDetail extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');

        if (empty($id)) {
            $this->response(['error' => 'Calendar ID is required'], 400);
        }

        CalendarUser::check($id, $this->user->id);

        $this->response(Calendar::findById($id), 200);
    }
}
