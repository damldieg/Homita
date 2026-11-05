<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Task;
use App\Models\TaskListUser;

class TaskCreate extends ControllerAbstract
{
    public function handle(): void
    {
        $taskListId = $this->getInputInt('task_list_id');
        $title = $this->getInputString('title');

        if (empty($taskListId) || empty($title)) {
            $this->response(['error' => 'task_list_id and title are required'], 400);
        }

        TaskListUser::check($taskListId, $this->user->id);

        $this->response(Task::create($taskListId, $title), 201);
    }
}
