<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\TaskListUser;

class TaskListUserDelete extends ControllerAbstract
{
    public function handle(): void
    {
        $taskListId = $this->getInputInt('task_list_id');
        $userId = $this->getInputInt('user_id');

        if (empty($taskListId) || empty($userId)) {
            $this->response(['error' => 'task_list_id and user_id are required'], 400);
        }

        TaskListUser::check($taskListId, $this->user->id);

        if ($this->user->id === $userId) {
            $this->response(['error' => 'User cannot remove themselves'], 400);
        }

        TaskListUser::removeUser($taskListId, $userId);

        $this->response(['status' => 'ok']);
    }
}
