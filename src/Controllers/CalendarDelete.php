<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Calendar;
use App\Models\CalendarUser;

class CalendarDelete extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');

        if (empty($id)) {
            $this->response(['error' => 'Calendar ID is required'], 400);
        }

        $role = CalendarUser::check($id, $this->user->id);

        if ($role->role !== 'owner') {
            $this->response(['error' => 'Only owner can delete the calendar'], 403);
        }

        Calendar::findById($id)->delete();

        $this->response(['success' => true], 200);
    }
}
