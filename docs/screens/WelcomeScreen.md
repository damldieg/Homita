# Screen: WelcomeScreen

## Descripción
La pantalla de bienvenida es el punto de entrada inicial para usuarios no autenticados. Presenta la marca de la aplicación y ofrece las opciones de inicio de sesión y registro.

## Funcionamiento
- Al iniciarse, comprueba si existe una sesión activa a través de la navegación global.
- Carga la configuración del sistema para determinar si el registro de nuevos usuarios está permitido.
- Muestra botones para navegar hacia `LoginScreen` o `RegisterScreen`.

## Endpoints Llamados
- `GET /config`: Para verificar `allow_registration`.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/WelcomeScreen.kt`
- `app/android/app/src/main/java/com/lito/planify/viewmodel/AuthViewModel.kt`
