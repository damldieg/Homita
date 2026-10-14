<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Calendar;
use App\Models\TaskList;

abstract class DashboardControllerAbstract extends ControllerAbstract
{
    /** Calendarios y listas del usuario con su marca de dashboard. */
    protected function config(): array
    {
        return [
            'calendars' => array_map($this->item(...), Calendar::findByUser($this->user->id)),
            'task_lists' => array_map($this->item(...), TaskList::findByUser($this->user->id)),
        ];
    }

    private function item(Calendar|TaskList $model): array
    {
        return [
            'id' => $model->id,
            'name' => $model->name,
            'color' => $model->color,
            'dashboard' => $model->dashboard === 1,
        ];
    }
}
