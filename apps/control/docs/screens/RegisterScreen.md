# Screen: RegisterScreen

## Descripción
Permite a nuevos usuarios crear una cuenta en la aplicación.

## Funcionamiento
- Solicita `Nombre`, `Email` y `Contraseña`.
- Realiza el registro y, tras el éxito, inicia sesión automáticamente guardando el token.
- Solo es accesible si `allow_registration` es true en la configuración.

## Endpoints Llamados
- `POST /user/create`: Para registrar el nuevo usuario.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/AuthScreens.kt` (Contiene `RegisterScreen`)
- `app/android/app/src/main/java/com/lito/planify/viewmodel/AuthViewModel.kt`
