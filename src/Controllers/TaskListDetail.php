<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\TaskList;
use App\Models\TaskListUser;

class TaskListDetail extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');

        if (empty($id)) {
            $this->response(['error' => 'Task list ID is required'], 400);
        }

        TaskListUser::check($id, $this->user->id);

        $this->response(TaskList::findById($id), 200);
    }
}
