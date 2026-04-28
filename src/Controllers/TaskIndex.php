<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Task;
use App\Models\TaskListUser;

class TaskIndex extends ControllerAbstract
{
    public function handle(): void
    {
        $taskListId = $this->getInputInt('task_list_id');

        if ($taskListId) {
            TaskListUser::check($taskListId, $this->user->id);
        }

        $this->response(Task::findWithFilters($this->user->id, $this->input), 200);
    }
}
