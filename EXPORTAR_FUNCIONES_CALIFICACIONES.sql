-- CONSULTA DE SOLO LECTURA. NO modifica datos ni ejecuta cierre.
-- Exportar el resultado como CSV/JSON para completar la integración oficial.
select n.nspname as esquema, p.proname as funcion,
       pg_get_function_identity_arguments(p.oid) as argumentos,
       pg_get_functiondef(p.oid) as definicion
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prokind='f'
  and (p.proname ilike '%project%' or p.proname ilike '%grade%'
       or p.proname ilike '%calific%' or p.proname ilike '%academic%'
       or p.proname ilike '%certificate%')
order by p.proname;
