<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Task;

class TaskDetail extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');

        if (empty($id)) {
            $this->response(['error' => 'Task ID is required'], 400);
        }

        $this->response(Task::findByIdAndUser($id, $this->user->id), 200);
    }
}
