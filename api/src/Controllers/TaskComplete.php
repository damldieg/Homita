<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Task;

class TaskComplete extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');
        $completed = $this->getInputBool('completed');

        if (empty($id) || $completed === null) {
            $this->response(['error' => 'Task ID and completed are required'], 400);
        }

        $this->response(Task::findByIdAndUser($id, $this->user->id)->setCompleted($completed), 200);
    }
}
