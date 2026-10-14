<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\CalendarUser;
use App\Models\TaskListUser;
use InvalidArgumentException;

class DashboardUpdate extends DashboardControllerAbstract
{
    public function handle(): void
    {
        $calendarIds = $this->ids('calendar_ids');
        $taskListIds = $this->ids('task_list_ids');

        foreach ($calendarIds ?? [] as $id) {
            if (!CalendarUser::exists($id, $this->user->id)) throw new InvalidArgumentException('Invalid calendar');
        }

        foreach ($taskListIds ?? [] as $id) {
            if (!TaskListUser::exists($id, $this->user->id)) throw new InvalidArgumentException('Invalid task list');
        }

        if ($calendarIds !== null) {
            CalendarUser::setDashboard($this->user->id, $calendarIds);
        }

        if ($taskListIds !== null) {
            TaskListUser::setDashboard($this->user->id, $taskListIds);
        }

        $this->response($this->config(), 200);
    }

    /** null si no se envía (no se toca); si se envía, lista de IDs sin duplicados. */
    private function ids(string $key): ?array
    {
        $ids = $this->getInput($key);

        if ($ids === null) {
            return null;
        }

        if (!is_array($ids) || !array_is_list($ids)) {
            throw new InvalidArgumentException($key.' must be a list');
        }

        foreach ($ids as $id) {
            if (!is_int($id) || $id < 1) {
                throw new InvalidArgumentException($key.' must be a list of IDs');
            }
        }

        return array_values(array_unique($ids));
    }
}
