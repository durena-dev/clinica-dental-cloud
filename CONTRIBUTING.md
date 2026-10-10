# Guía de contribución

## Ramas

Usamos GitHub Flow. La rama `main` está protegida: no se hace push directo; todo cambio entra por pull request.

Cada tarea se trabaja en una rama corta con nombre descriptivo:

- `feature/agenda-disponibilidad`
- `fix/validacion-fecha`
- `docs/readme-instalacion`
- `chore/configurar-ci`

## Commits (Conventional Commits)

Formato: `tipo: descripción corta en minúsculas`

| Tipo | Uso |
|---|---|
| `feat` | Nueva funcionalidad |
| `fix` | Corrección de un error |
| `docs` | Documentación |
| `chore` | Configuración, dependencias, tareas de mantenimiento |
| `test` | Pruebas |
| `refactor` | Cambio de código sin cambiar el comportamiento |

Ejemplos: `feat: agregar endpoint de citas`, `fix: validar traslape de horarios`, `docs: actualizar instrucciones de instalación`.

## Pull requests

1. Crear la rama desde `main` actualizada.
2. Abrir el pull request hacia `main` y completar la plantilla.
3. Necesita al menos una aprobación de otro integrante (nadie aprueba su propio PR).
4. El pipeline debe pasar antes de hacer merge (cuando exista).
5. Hacer merge y borrar la rama.

## Secretos

Nunca se suben contraseñas, tokens ni cadenas de conexión reales. Se usan variables de entorno (`.env` está en `.gitignore`; la referencia es `.env.example`).
