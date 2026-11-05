<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\TaskListUser;

class TaskListUserIndex extends ControllerAbstract
{
    public function handle(): void
    {
        $taskListId = $this->getInputInt('task_list_id');

        if ($taskListId === 0 || $taskListId === null) {
            $this->response(['error' => 'task_list_id is required'], 400);
        }

        TaskListUser::check($taskListId, $this->user->id);

        $this->response(TaskListUser::findUsersByTaskList($taskListId));
    }
}
