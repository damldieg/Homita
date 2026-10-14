<?php declare(strict_types=1);

namespace App\Controllers;

use App\Utils\Router;

$router = new Router();

$router->get('/config', static fn () => new Config()->handle());

$router->post('/user/create', static fn () => new UserCreate()->handle());
$router->post('/user/auth', static fn () => new UserAuth()->handle());
$router->patch('/user/update', static fn () => new UserUpdate()->middlewareAuth()->handle());

$router->get('/calendar', static fn () => new CalendarIndex()->middlewareAuth()->handle());
$router->get('/calendar/detail', static fn () => new CalendarDetail()->middlewareAuth()->handle());
$router->post('/calendar/create', static fn () => new CalendarCreate()->middlewareAuth()->handle());
$router->patch('/calendar/update', static fn () => new CalendarUpdate()->middlewareAuth()->handle());
$router->delete('/calendar/delete', static fn () => new CalendarDelete()->middlewareAuth()->handle());
$router->post('/calendar/user', static fn () => new CalendarUserCreate()->middlewareAuth()->handle());
$router->get('/calendar/user', static fn () => new CalendarUserIndex()->middlewareAuth()->handle());
$router->delete('/calendar/user', static fn () => new CalendarUserDelete()->middlewareAuth()->handle());

$router->get('/dashboard', static fn () => new DashboardIndex()->middlewareAuth()->handle());
$router->post('/dashboard/update', static fn () => new DashboardUpdate()->middlewareAuth()->handle());

$router->get('/person', static fn () => new PersonIndex()->middlewareAuth()->handle());
$router->post('/person/create', static fn () => new PersonCreate()->middlewareAuth()->handle());
$router->patch('/person/update', static fn () => new PersonUpdate()->middlewareAuth()->handle());
$router->delete('/person/delete', static fn () => new PersonDelete()->middlewareAuth()->handle());

$router->get('/routine', static fn () => new RoutineIndex()->middlewareAuth()->handle());
$router->get('/routine/detail', static fn () => new RoutineDetail()->middlewareAuth()->handle());
$router->post('/routine/create', static fn () => new RoutineCreate()->middlewareAuth()->handle());
$router->patch('/routine/update', static fn () => new RoutineUpdate()->middlewareAuth()->handle());
$router->patch('/routine/alarm', static fn () => new RoutineAlarm()->middlewareAuth()->handle());
$router->delete('/routine/delete', static fn () => new RoutineDelete()->middlewareAuth()->handle());

$router->get('/event', static fn () => new EventIndex()->middlewareAuth()->handle());
$router->get('/event/detail', static fn () => new EventDetail()->middlewareAuth()->handle());
$router->post('/event/create', static fn () => new EventCreate()->middlewareAuth()->handle());
$router->patch('/event/update', static fn () => new EventUpdate()->middlewareAuth()->handle());
$router->delete('/event/delete', static fn () => new EventDelete()->middlewareAuth()->handle());
$router->patch('/event/alarm', static fn () => new EventAlarm()->middlewareAuth()->handle());

$router->get('/task-list', static fn () => new TaskListIndex()->middlewareAuth()->handle());
$router->get('/task-list/detail', static fn () => new TaskListDetail()->middlewareAuth()->handle());
$router->post('/task-list/create', static fn () => new TaskListCreate()->middlewareAuth()->handle());
$router->patch('/task-list/update', static fn () => new TaskListUpdate()->middlewareAuth()->handle());
$router->delete('/task-list/delete', static fn () => new TaskListDelete()->middlewareAuth()->handle());
$router->post('/task-list/user', static fn () => new TaskListUserCreate()->middlewareAuth()->handle());
$router->get('/task-list/user', static fn () => new TaskListUserIndex()->middlewareAuth()->handle());
$router->delete('/task-list/user', static fn () => new TaskListUserDelete()->middlewareAuth()->handle());

$router->get('/task', static fn () => new TaskIndex()->middlewareAuth()->handle());
$router->get('/task/detail', static fn () => new TaskDetail()->middlewareAuth()->handle());
$router->post('/task/create', static fn () => new TaskCreate()->middlewareAuth()->handle());
$router->patch('/task/update', static fn () => new TaskUpdate()->middlewareAuth()->handle());
$router->patch('/task/complete', static fn () => new TaskComplete()->middlewareAuth()->handle());
$router->patch('/task/order', static fn () => new TaskOrder()->middlewareAuth()->handle());
$router->delete('/task/delete', static fn () => new TaskDelete()->middlewareAuth()->handle());

$router->dispatch($_SERVER['REQUEST_METHOD'] ?? 'GET', $_SERVER['REQUEST_URI'] ?? '/');
