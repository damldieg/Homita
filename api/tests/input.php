<?php declare(strict_types=1);

require dirname(__DIR__).'/src/autoload.php';

use App\Controllers\ControllerAbstract;

function check(bool $condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

// Controlador mínimo para leer la entrada como lo hacen los reales
$controller = new class extends ControllerAbstract {
    public function handle(): void {}

    public function bool(array $input, string $key, ?bool $default = null): ?bool
    {
        $this->input = $input;

        return $this->getInputBool($key, $default);
    }
};

check($controller->bool([], 'widget', true) === true, 'A missing boolean takes its default');
check($controller->bool(['widget' => null], 'widget', true) === true, 'A null boolean takes its default');
check($controller->bool([], 'completed') === null, 'A missing boolean without default is null');
check($controller->bool(['widget' => false], 'widget', true) === false, 'JSON false is kept');
check($controller->bool(['widget' => true], 'widget', false) === true, 'JSON true is kept');
check($controller->bool(['widget' => 'false'], 'widget', true) === false, 'Query string "false" is false');
check($controller->bool(['widget' => '1'], 'widget') === true, 'Query string "1" is true');
check($controller->bool(['widget' => 'maybe'], 'widget', true) === true, 'An invalid value takes the default');
echo "Input behavioral checks passed\n";
