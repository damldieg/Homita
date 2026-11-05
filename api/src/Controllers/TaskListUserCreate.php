<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\User;
use App\Models\TaskListUser;

class TaskListUserCreate extends ControllerAbstract
{
    public function handle(): void
    {
        $taskListId = $this->getInputInt('task_list_id');
        $email = $this->getInputEmail('email');

        if (empty($taskListId) || empty($email)) {
            $this->response(['error' => 'Task list ID and email are required'], 400);
        }

        TaskListUser::check($taskListId, $this->user->id);

        $target = User::findByEmail($email);

        if (TaskListUser::exists($taskListId, $target->id) === false) {
            TaskListUser::create($taskListId, $target->id, 'viewer');
        }

        $this->response($target, 200);
    }
}
