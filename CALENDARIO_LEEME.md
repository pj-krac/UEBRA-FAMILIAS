# Calendario institucional para UEBRA Familias

Cambios: pestaña de calendario por representado, lista automática de próximas fechas (desde hoy, durante los próximos 365 días), sin campos de período ni botón Consultar, carga/error/vacío, escape HTML, lectura por RPC, control de respuestas antiguas al cambiar de estudiante, navegación con foco al panel y controles adaptables a móvil.

Estado: frontend integrado; requiere aprobar y desplegar CALENDARIO_SUPABASE_PENDIENTE.sql para funcionar con datos reales. No se ejecutó SQL ni se llamó al servidor. Si falta la función, la pantalla muestra un mensaje de acceso aún no habilitado. No hay fallback a lectura directa ni se abren permisos públicos.

La propuesta valida auth.uid(), representante activo, vínculo activo autorizado, contraseña cambiada y jornada derivada del curso del estudiante en servidor. Devuelve únicamente fechas activas aprobadas para familias y de alcance institucional o de esa jornada. publicar_familias comienza en false: no expone motivos existentes automáticamente. El calendario origen representa fechas sin clase; no se alteran cálculos de asistencia ni se añaden eventos generales.

Antes de aprobar: confirmar tablas, tipos, columnas y propietario de la función con privilegios mínimos; revisar políticas RLS/grants ya existentes para impedir que una lectura directa eluda la función. Verificar que must_change_password=false sea la condición usada por las funciones desplegadas. Revisar específicamente policies amplias del SQL original UEBRA+. La función security definer necesita revisión del administrador del backend.

Después de aprobación: publicar individualmente las fechas autorizadas mediante publicar_familias=true con cuenta administrativa. La pantalla administrativa actual conserva su funcionamiento; no incorpora un control de publicación dependiente de un esquema aún no aprobado.

Pruebas de aceptación pendientes en servidor: representante con uno/dos estudiantes en jornadas distintas; vínculo inactivo; representante inactivo; contraseña pendiente; estudiante ajeno; sin sesión; fechas no publicadas; registros inactivos; fecha institucional; fecha de otra jornada; cambio rápido de representado; red desconectada y pantalla móvil. La validación local de sintaxis no sustituye estas pruebas.

Se conserva el ZIP original del escritorio sin cambios. UEBRA+ y su módulo de cierre de año no se modificaron en esta integración. No se ejecutó admin_execute_school_year_closure.

Entregar index.html junto con los recursos originales de este ZIP. No reemplazar el index.html de UEBRA+ con este archivo: corresponde al portal UEBRA Familias.
