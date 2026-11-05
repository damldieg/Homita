<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\TaskList;

class TaskListIndex extends ControllerAbstract
{
    public function handle(): void
    {
        $this->response(TaskList::findByUser($this->user->id), 200);
    }
}
