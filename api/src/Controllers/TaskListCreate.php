<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\TaskList;
use App\Models\TaskListUser;

class TaskListCreate extends ControllerAbstract
{
    public function handle(): void
    {
        $name = $this->getInputString('name');
        $color = $this->getInputString('color');
        $sort = $this->getInputString('sort', 'updated_at');
        $widget = $this->getInputBool('widget', true);
        $dashboard = $this->getInputBool('dashboard', true);

        if (empty($name)) {
            $this->response(['error' => 'Name is required'], 400);
        }

        if (in_array($sort, ['updated_at', 'title', 'custom'], true) === false) {
            $this->response(['error' => 'Sort must be updated_at, title or custom'], 400);
        }

        $taskList = TaskList::create($name, $color ?: '#6923E2', $sort);

        TaskListUser::create($taskList->id, $this->user->id, 'owner', $widget, $dashboard);

        $this->response($taskList, 201);
    }
}
