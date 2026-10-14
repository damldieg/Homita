<?php declare(strict_types=1);

namespace App\Controllers;

class DashboardIndex extends DashboardControllerAbstract
{
    public function handle(): void
    {
        $this->response($this->config(), 200);
    }
}
