<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\TaskList;
use App\Models\TaskListUser;

class TaskListDelete extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');

        if (empty($id)) {
            $this->response(['error' => 'Task list ID is required'], 400);
        }

        $role = TaskListUser::check($id, $this->user->id);

        if ($role->role !== 'owner') {
            $this->response(['error' => 'Only owner can delete the task list'], 403);
        }

        TaskList::findById($id)->delete();

        $this->response(['success' => true], 200);
    }
}
