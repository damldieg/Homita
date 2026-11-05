<?php declare(strict_types=1);

namespace App\Controllers;

use App\Utils\Config as ConfigUtils;

class Config extends ControllerAbstract
{
    public function handle(): void
    {
        $this->response(ConfigUtils::get('public'));
    }
}
