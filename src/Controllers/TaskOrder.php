<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Task;

class TaskOrder extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');
        $positionRaw = $this->getInput('position');

        if (empty($id) || $positionRaw === null) {
            $this->response(['error' => 'id and position are required'], 400);
        }

        $position = intval($positionRaw);

        if ($position < 0) {
            $this->response(['error' => 'position must be zero or positive'], 400);
        }

        $task = Task::findByIdAndUser($id, $this->user->id);

        $this->response($task->moveToPosition($position), 200);
    }
}
