<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\Task;

class TaskUpdate extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');
        $title = $this->getInputString('title');

        if (empty($id) || empty($title)) {
            $this->response(['error' => 'Task ID and title are required'], 400);
        }

        $this->response(Task::findByIdAndUser($id, $this->user->id)->update($title), 200);
    }
}
