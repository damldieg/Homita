<?php declare(strict_types=1);

namespace App\Controllers;

use App\Models\TaskList;
use App\Models\TaskListUser;

class TaskListUpdate extends ControllerAbstract
{
    public function handle(): void
    {
        $id = $this->getInputInt('id');
        $name = $this->getInputString('name');
        $color = $this->getInputString('color');
        $sort = $this->getInputString('sort');
        $widget = $this->getInputBool('widget', true);

        if (empty($id) || empty($name) || empty($color) || empty($sort)) {
            $this->response(['error' => 'Task list ID, name, color and sort are required'], 400);
        }

        if (in_array($sort, ['updated_at', 'title', 'custom'], true) === false) {
            $this->response(['error' => 'Sort must be updated_at, title or custom'], 400);
        }

        $role = TaskListUser::check($id, $this->user->id);

        TaskListUser::setWidget($id, $this->user->id, $widget);

        $this->response(TaskList::findById($id)->update($name, $color, $sort), 200);
    }
}
