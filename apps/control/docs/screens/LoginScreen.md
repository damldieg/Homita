# Screen: LoginScreen

## Descripción
Permite a los usuarios existentes acceder a su cuenta mediante correo electrónico y contraseña.

## Funcionamiento
- Gestiona campos de texto para `email` y `password`.
- Proporciona validación visual de errores devueltos por la API.
- Al autenticarse correctamente, el `token` devuelto se guarda localmente (SessionManager) y se configura en el cliente de API (Retrofit).

## Endpoints Llamados
- `POST /user/auth`: Para validar credenciales y obtener el token.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/AuthScreens.kt` (Contiene `LoginScreen`)
- `app/android/app/src/main/java/com/lito/planify/viewmodel/AuthViewModel.kt`
- `app/android/app/src/main/java/com/lito/planify/data/local/SessionManager.kt`
