# Agenda escolar — uso y activación

## Entrega
UEBRA+: Administrar → Calendario institucional → Administrar agenda.
Elegir fecha, tipo, título, asignatura opcional, destinatarios, asistencia y observaciones. Marcar Publicar en Familias para hacerlo visible. Sin marcar, queda como borrador. Editar o desactivar, sin eliminar eventos.
Familias: misma pestaña de calendario, fechas automáticas durante los próximos 365 días; muestra tipo, título, asignatura, observaciones y alcance. Fechas sin clase anteriores muestran No hay clases ni asistencia.

## Activación pendiente
1. Respaldar/revisar el esquema vigente en Supabase. Confirmar que family_student_school_calendar del paso anterior funciona.
2. Revisar y aprobar AGENDA_SUPABASE_PENDIENTE.sql. Requiere tablas existentes courses, profiles, students, family_members, student_family y función is_admin.
3. Ejecutar una sola vez en SQL Editor tras aprobación. La creación de la política no es idempotente; si ya existe, no repetir sin revisión. El script es transaccional, no borra fechas ni inserta eventos.
4. Actualizar UEBRA+ con index.html, agenda.js y sw.js del ZIP (preferible desplegar el conjunto completo). Actualizar Familias con su ZIP independiente. No intercambiar los index de los dos portales.
5. Crear un evento de prueba desde ADMIN como borrador; verificar que no aparezca en Familias. Publicarlo y comprobar que solo lo vea el representado del curso/jornada correcto. Desactivarlo y verificar que deje de aparecer.

Mientras no exista la nueva función, Familias conserva las fechas del calendario anterior usando su RPC autorizada. No lee tablas directamente como alternativa. Administración mostrará que la agenda aún no está habilitada.

## Asistencia
El aviso No hay clases ni asistencia de la agenda es informativo. Para excluir realmente el día del cálculo de asistencia, registrarlo también en Fechas sin clase. Pruebas/lecciones/proyectos no cambian esos cálculos. No duplicar un feriado ya publicado como evento de agenda salvo que se quiera mostrar ambas entradas; la lista conserva ambas fuentes sin deduplicación automática.

## Seguridad y validación
RLS de agenda limita lectura/escritura directa a ADMIN activo; representantes leen mediante RPC que valida sesión, vínculo y contraseña cambiada y deriva curso/jornada en servidor. Solo devuelve eventos activos publicados. Verificar policies/grants existentes y propietario de función antes de ejecutar el SQL. Docentes no tienen habilitada creación en esta versión.
Sintaxis validada de ambos HTML, agenda.js y sw.js. Comprobado bloque original de cierre de año sin cambios. No se ejecutó SQL ni se conectó al servidor. Pendientes: prueba visual con sesiones reales y pruebas de acceso cruzado, alcance por curso/jornada, borradores e inactivos. No se generaron fechas o actividades ficticias en la base.
