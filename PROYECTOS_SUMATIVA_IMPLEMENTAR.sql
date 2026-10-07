-- PROYECTOS FLEXIBLES: configuración y cálculo oficial. PENDIENTE DE APROBACIÓN.
-- Reemplaza tres funciones de cálculo/lectura. No modifica aportes ni cierre.
begin;
create table if not exists public.flexible_sumative_projects(
 id uuid primary key default gen_random_uuid(),course_id uuid not null references public.courses(id),
 anio_lectivo text not null check(length(anio_lectivo) between 4 and 30),
 trimestre smallint not null check(trimestre between 1 and 3),
 nombre text not null check(length(btrim(nombre)) between 1 and 180),
 confirmado boolean not null default false,
 created_at timestamptz not null default now()
);
create table if not exists public.flexible_sumative_members(
 project_id uuid not null references public.flexible_sumative_projects(id),
 course_id uuid not null references public.courses(id),
 anio_lectivo text not null,trimestre smallint not null,
 asignatura text not null,
 primary key(project_id,asignatura),
 unique(course_id,anio_lectivo,trimestre,asignatura)
);
alter table public.flexible_sumative_projects enable row level security;
alter table public.flexible_sumative_members enable row level security;
revoke all on public.flexible_sumative_projects,public.flexible_sumative_members from anon,authenticated;
create table if not exists public.flexible_sumative_activation(course_id uuid not null references public.courses(id),trimestre smallint not null check(trimestre between 1 and 3),anio_lectivo text not null,activated_at timestamptz not null default now(),primary key(course_id,trimestre));
alter table public.flexible_sumative_activation enable row level security;
revoke all on public.flexible_sumative_activation from anon,authenticated;
create or replace function public.admin_save_flexible_sumative_project(
 p_course_id uuid,p_anio text,p_trimestre integer,p_nombre text,p_asignaturas text[],p_confirmado boolean,p_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_count integer; v_subject text;
begin
 p_anio:=btrim(p_anio);
 if not public.is_grade_admin() or not exists(select 1 from public.profiles where id=auth.uid() and activo is true) then raise exception 'Acceso no autorizado'; end if;
 if exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre) then raise exception 'Este curso/trimestre ya está activado; sus grupos están bloqueados'; end if;
 -- Serializa cambios del mismo curso/año/trimestre para impedir reservas duplicadas.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_course_id::text||p_anio||p_trimestre::text,0));
 if exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre) then raise exception 'Curso/trimestre ya activado'; end if;
 if p_anio is null or length(btrim(p_anio)) not between 4 and 30 or (p_trimestre is null or p_trimestre not between 1 and 3) or p_nombre is null or length(btrim(p_nombre)) not between 1 and 180 or p_confirmado is null then raise exception 'Datos inválidos'; end if;
 if not exists(select 1 from public.courses where id=p_course_id and activo is true) then raise exception 'Curso inválido'; end if;
 select count(distinct x) into v_count from unnest(p_asignaturas) x where nullif(btrim(x),'') is not null;
 if v_count=0 or v_count<>cardinality(p_asignaturas) then raise exception 'Seleccione asignaturas únicas'; end if;
 if exists(select 1 from unnest(p_asignaturas) x group by public.normalizar_asignatura(x) having count(*)>1) then raise exception 'Asignaturas equivalentes repetidas'; end if;
 foreach v_subject in array p_asignaturas loop
 if not public.subject_participates_project(p_course_id,v_subject) then raise exception 'Asignatura no elegible: %',v_subject; end if;
 if exists(select 1 from public.flexible_sumative_members m where m.course_id=p_course_id and m.anio_lectivo=p_anio and m.trimestre=p_trimestre and (p_id is null or m.project_id<>p_id) and public.normalizar_asignatura(m.asignatura)=public.normalizar_asignatura(v_subject)) then raise exception 'La materia ya pertenece a otro proyecto: %',v_subject; end if;
 if not exists(select 1 from public.schedules where course_id=p_course_id and asignatura=v_subject and activo is true) then raise exception 'Asignatura sin horario activo: %',v_subject; end if;
 end loop;
 if p_id is not null then
 select id into v_id from public.flexible_sumative_projects where id=p_id and course_id=p_course_id and anio_lectivo=p_anio and trimestre=p_trimestre and confirmado is false for update;
 if not found then raise exception 'El proyecto confirmado no puede modificarse'; end if;
 update public.flexible_sumative_projects set nombre=btrim(p_nombre),confirmado=p_confirmado where id=v_id;
 delete from public.flexible_sumative_members where project_id=v_id;
 else
 insert into public.flexible_sumative_projects(course_id,anio_lectivo,trimestre,nombre,confirmado) values(p_course_id,btrim(p_anio),p_trimestre,btrim(p_nombre),p_confirmado) returning id into v_id;
 end if;
 insert into public.flexible_sumative_members(project_id,course_id,anio_lectivo,trimestre,asignatura)
 select v_id,p_course_id,btrim(p_anio),p_trimestre,x from unnest(p_asignaturas) x;
 return v_id;
end;
$$;
create or replace function public.flexible_sumative_project_groups(p_course_id uuid,p_anio text,p_trimestre integer)
returns table(id uuid,nombre text,confirmado boolean,asignaturas text[])
language plpgsql stable security definer set search_path='' as $$
declare v_admin boolean;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and activo is true) then raise exception 'Acceso no autorizado'; end if;
 v_admin:=public.is_admin();
 if not v_admin and not exists(select 1 from public.schedules s join public.teachers t on t.id=s.teacher_id where t.profile_id=auth.uid() and t.activo is true and s.activo is true and s.course_id=p_course_id) then raise exception 'Acceso no autorizado'; end if;
 return query select p.id,p.nombre,p.confirmado,array_agg(m.asignatura order by m.asignatura)
 from public.flexible_sumative_projects p join public.flexible_sumative_members m on m.project_id=p.id
 where p.course_id=p_course_id and p.anio_lectivo=p_anio and p.trimestre=p_trimestre
 and (v_admin or exists(select 1 from public.flexible_sumative_members own join public.schedules s on s.course_id=own.course_id and s.asignatura=own.asignatura and s.activo is true join public.teachers t on t.id=s.teacher_id and t.activo is true where own.project_id=p.id and t.profile_id=auth.uid()))
 group by p.id,p.nombre,p.confirmado order by p.created_at,p.id;
end;
$$;
revoke all on function public.admin_save_flexible_sumative_project(uuid,text,integer,text,text[],boolean,uuid) from public,anon;
revoke all on function public.flexible_sumative_project_groups(uuid,text,integer) from public,anon;
grant execute on function public.admin_save_flexible_sumative_project(uuid,text,integer,text,text[],boolean,uuid) to authenticated;
grant execute on function public.flexible_sumative_project_groups(uuid,text,integer) to authenticated;


create or replace function public.admin_activate_flexible_sumative(p_course_id uuid,p_anio text,p_trimestre integer)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_grade_admin() then raise exception 'Acceso no autorizado'; end if;
 p_anio:=btrim(p_anio);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_course_id::text||p_anio||p_trimestre::text,0));
 if exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre) then raise exception 'Curso/trimestre ya activado'; end if;
 if p_anio is null or length(p_anio) not between 4 and 30 or p_trimestre is null or p_trimestre not between 1 and 3 then raise exception 'Selección inválida'; end if;
 if exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre) then raise exception 'Ya está activado; no se permite cambiar de año sobre los mismos aportes'; end if;
 if not exists(select 1 from public.flexible_sumative_projects p where p.course_id=p_course_id and p.anio_lectivo=p_anio and p.trimestre=p_trimestre) then raise exception 'No hay proyectos'; end if;
 if exists(select 1 from public.flexible_sumative_projects p where p.course_id=p_course_id and p.anio_lectivo=p_anio and p.trimestre=p_trimestre and not p.confirmado) then raise exception 'Confirme todos los proyectos antes de activar'; end if;
 if exists(select 1 from public.flexible_sumative_projects p where p.course_id=p_course_id and p.anio_lectivo=p_anio and p.trimestre=p_trimestre and not exists(select 1 from public.flexible_sumative_members m where m.project_id=p.id)) then raise exception 'Hay proyectos sin materias'; end if;
 if exists(select 1 from public.flexible_sumative_members m where m.course_id=p_course_id and m.anio_lectivo=p_anio and m.trimestre=p_trimestre group by public.normalizar_asignatura(m.asignatura) having count(*)>1) then raise exception 'Materias equivalentes repetidas'; end if;
 if exists(select 1 from public.flexible_sumative_members m where m.course_id=p_course_id and m.anio_lectivo=p_anio and m.trimestre=p_trimestre and (not public.subject_participates_project(p_course_id,m.asignatura) or not exists(select 1 from public.schedules s where s.course_id=p_course_id and s.activo and public.normalizar_asignatura(s.asignatura)=public.normalizar_asignatura(m.asignatura)))) then raise exception 'Hay participantes sin asignación válida'; end if;
 if exists(select 1 from public.schedules s where s.course_id=p_course_id and s.activo and public.subject_participates_project(p_course_id,s.asignatura) and not exists(select 1 from public.flexible_sumative_members m join public.flexible_sumative_projects p on p.id=m.project_id where p.course_id=p_course_id and p.anio_lectivo=p_anio and p.trimestre=p_trimestre and p.confirmado and public.normalizar_asignatura(m.asignatura)=public.normalizar_asignatura(s.asignatura))) then raise exception 'Faltan asignaturas por asignar a un proyecto'; end if;
 insert into public.flexible_sumative_activation(course_id,trimestre,anio_lectivo) values(p_course_id,p_trimestre,p_anio);
end;
$$;
revoke all on function public.admin_activate_flexible_sumative(uuid,text,integer) from public,anon;
grant execute on function public.admin_activate_flexible_sumative(uuid,text,integer) to authenticated;

-- Helper interno: conserva el cálculo anterior mientras el curso/trimestre no se active.
create or replace function public.project_subject_group_status(p_student_id uuid,p_course_id uuid,p_asignatura text,p_trimestre smallint)
returns table(asignaturas_esperadas integer,aportes_registrados integer,completo boolean,promedio numeric)
language plpgsql stable security definer set search_path='' as $$
declare v_year text;v_project uuid;
begin
 select a.anio_lectivo into v_year from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre;
 if not found then return query select * from public.project_status(p_student_id,p_course_id,p_trimestre);return;end if;
 select p.id into v_project from public.flexible_sumative_projects p join public.flexible_sumative_members m on m.project_id=p.id where p.course_id=p_course_id and p.anio_lectivo=v_year and p.trimestre=p_trimestre and p.confirmado and public.normalizar_asignatura(m.asignatura)=public.normalizar_asignatura(p_asignatura);
 if not found then return query select 0,0,false,null::numeric;return;end if;
 return query
 with members as(select distinct public.normalizar_asignatura(m.asignatura) subject from public.flexible_sumative_members m where m.project_id=v_project),
 contributions as(select public.normalizar_asignatura(g.asignatura) subject,avg(g.nota_aporte)::numeric score from public.project_grades g where g.student_id=p_student_id and g.course_id=p_course_id and g.trimestre=p_trimestre and g.nota_aporte is not null group by public.normalizar_asignatura(g.asignatura)),
 totals as(select count(*)::integer expected,count(c.score)::integer registered,avg(c.score)::numeric mean from members m left join contributions c using(subject))
 select expected,registered,expected>0 and expected=registered,case when expected>0 and expected=registered then mean else null::numeric end from totals;
end;
$$;
revoke all on function public.project_subject_group_status(uuid,uuid,text,smallint) from public,anon,authenticated;

-- RPC de contexto para mostrar grupo y modo activo en la captura ya existente.
create or replace function public.project_subject_group_context(p_course_id uuid,p_asignatura text,p_trimestre smallint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_year text;v_result jsonb;
begin
 if not (public.is_grade_admin() or public.can_manage_grade_assignment(p_course_id,p_asignatura)) then raise exception 'Acceso no autorizado'; end if;
 select a.anio_lectivo into v_year from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre;
 if not found then return jsonb_build_object('activo',false);end if;
 select jsonb_build_object('activo',true,'anio_lectivo',v_year,'nombre',p.nombre,'asignaturas',jsonb_agg(m.asignatura order by m.asignatura)) into v_result
 from public.flexible_sumative_projects p join public.flexible_sumative_members m on m.project_id=p.id
 where p.course_id=p_course_id and p.anio_lectivo=v_year and p.trimestre=p_trimestre and p.confirmado
 and exists(select 1 from public.flexible_sumative_members own where own.project_id=p.id and public.normalizar_asignatura(own.asignatura)=public.normalizar_asignatura(p_asignatura)) group by p.id,p.nombre;
 return coalesce(v_result,jsonb_build_object('activo',true,'asignaturas',jsonb_build_array()));
end;
$$;
revoke all on function public.project_subject_group_context(uuid,text,smallint) from public,anon;
grant execute on function public.project_subject_group_context(uuid,text,smallint) to authenticated;

CREATE OR REPLACE FUNCTION public.subject_summative_grade(p_student_id uuid, p_course_id uuid, p_asignatura text, p_trimestre smallint)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_aporte numeric;
    v_promedio_proyecto numeric;
BEGIN

    IF NOT public.subject_participates_project(
        p_course_id,
        p_asignatura
    ) THEN
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM public.flexible_sumative_activation a WHERE a.course_id=p_course_id AND a.trimestre=p_trimestre) THEN
      SELECT AVG(pg.nota_aporte) INTO v_aporte FROM public.project_grades pg
      WHERE pg.student_id=p_student_id AND pg.course_id=p_course_id AND pg.trimestre=p_trimestre
      AND public.normalizar_asignatura(pg.asignatura)=public.normalizar_asignatura(p_asignatura);
    ELSE
    SELECT pg.nota_aporte
    INTO v_aporte
    FROM public.project_grades pg
    WHERE pg.student_id = p_student_id
      AND pg.course_id = p_course_id
      AND pg.trimestre = p_trimestre
      AND lower(trim(pg.asignatura)) =
          lower(trim(p_asignatura))
    LIMIT 1;

    END IF;
    -- El docente todavía no ha registrado su aporte.
    IF v_aporte IS NULL THEN
        RETURN NULL;
    END IF;

    -- Esta función ahora devuelve NULL mientras el proyecto
    -- no esté completo.
    SELECT ps.promedio INTO v_promedio_proyecto
    FROM public.project_subject_group_status(p_student_id,p_course_id,p_asignatura,p_trimestre) ps;

    IF v_promedio_proyecto IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN ROUND(
        (v_aporte + v_promedio_proyecto) / 2.0,
        2
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.project_subject_roster(p_course_id uuid, p_asignatura text, p_trimestre smallint)
 RETURNS TABLE(student_id uuid, estudiante text, cedula text, nota_aporte numeric, asignaturas_esperadas integer, aportes_registrados integer, proyecto_completo boolean, promedio_proyecto numeric, promedio_formativo numeric, nota_sumativa numeric, nota_trimestral numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN

    -- --------------------------------------------------------
    -- SEGURIDAD
    -- Solo administrador o docente asignado a esa materia.
    -- --------------------------------------------------------

    IF NOT (
        public.is_grade_admin()
        OR public.can_manage_grade_assignment(
            p_course_id,
            p_asignatura
        )
    ) THEN
        RAISE EXCEPTION 'No autorizado para consultar estas calificaciones';
    END IF;

    -- La asignatura debe participar realmente en el proyecto.
    IF NOT public.subject_participates_project(
        p_course_id,
        p_asignatura
    ) THEN
        RAISE EXCEPTION 'La asignatura no participa en el proyecto interdisciplinario';
    END IF;


    RETURN QUERY

    SELECT
        st.id AS student_id,
        st.nombre AS estudiante,
        st.cedula,

        pg.nota_aporte,

        ps.asignaturas_esperadas,
        ps.aportes_registrados,
        ps.completo AS proyecto_completo,
        ps.promedio AS promedio_proyecto,

        public.formative_average(
            st.id,
            p_course_id,
            p_asignatura,
            p_trimestre
        ) AS promedio_formativo,

        public.subject_summative_grade(
            st.id,
            p_course_id,
            p_asignatura,
            p_trimestre
        ) AS nota_sumativa,

        public.subject_trimester_grade(
            st.id,
            p_course_id,
            p_asignatura,
            p_trimestre
        ) AS nota_trimestral

    FROM public.students st

    LEFT JOIN LATERAL (SELECT AVG(g.nota_aporte)::numeric AS nota_aporte FROM public.project_grades g
      WHERE g.student_id=st.id AND g.course_id=p_course_id AND g.trimestre=p_trimestre
      AND public.normalizar_asignatura(g.asignatura)=public.normalizar_asignatura(p_asignatura)) pg ON true

    CROSS JOIN LATERAL public.project_subject_group_status(
        st.id,
        p_course_id,
        p_asignatura,
        p_trimestre
    ) ps

    WHERE st.course_id = p_course_id
      AND st.estado = 'ACTIVO'

    ORDER BY st.nombre;

END;
$function$;

CREATE OR REPLACE FUNCTION public.family_student_project_detail(p_student_id uuid)
 RETURNS TABLE(asignatura text, asignatura_normalizada text, trimestre smallint, aplica_proyecto boolean, nota_aporte numeric, promedio_proyecto numeric, nota_sumativa numeric, promedio_formativo numeric, nota_trimestre numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

DECLARE
    v_course_id uuid;

BEGIN

    -- ========================================================
    -- 1. SEGURIDAD
    -- ========================================================

    IF NOT public.is_my_family_student(p_student_id) THEN
        RAISE EXCEPTION
        'No tiene permiso para consultar el detalle académico de este estudiante.';
    END IF;


    -- ========================================================
    -- 2. CURSO DEL ESTUDIANTE
    -- ========================================================

    SELECT s.course_id
    INTO v_course_id
    FROM public.students s
    WHERE s.id = p_student_id
    LIMIT 1;


    IF v_course_id IS NULL THEN
        RAISE EXCEPTION
        'No se encontró el curso del estudiante.';
    END IF;


    -- ========================================================
    -- 3. ASIGNATURAS CUANTITATIVAS DEL CURSO
    -- ========================================================

    RETURN QUERY

    WITH asignaturas AS (

        SELECT DISTINCT
            sc.asignatura::text AS nombre_asignatura,
            public.normalizar_asignatura(sc.asignatura)::text
                AS nombre_normalizado

        FROM public.schedules sc

        WHERE sc.course_id = v_course_id
          AND COALESCE(sc.activo, true) = true

          AND public.normalizar_asignatura(sc.asignatura)
              NOT IN (
                  'TUTORIA',
                  'ANIMACION_LECTURA',
                  'OVP'
              )
    ),

    trimestres AS (

        SELECT generate_series(1,3)::smallint AS numero

    )

    SELECT

        a.nombre_asignatura::text,

        a.nombre_normalizado::text,

        t.numero::smallint,

        public.subject_participates_project(
            v_course_id,
            a.nombre_asignatura
        )::boolean,


        -- APORTE DE LA ASIGNATURA AL PROYECTO
        (
            SELECT pg.nota_aporte
            FROM public.project_grades pg
            WHERE pg.student_id = p_student_id
              AND pg.course_id = v_course_id
              AND pg.trimestre = t.numero
              AND public.normalizar_asignatura(pg.asignatura)
                  = a.nombre_normalizado
            ORDER BY pg.updated_at DESC
            LIMIT 1
        )::numeric,


        -- PROMEDIO GENERAL DEL PROYECTO TRIMESTRAL
        CASE
            WHEN public.subject_participates_project(
                v_course_id,
                a.nombre_asignatura
            )
            THEN (SELECT ps.promedio FROM public.project_subject_group_status(p_student_id,v_course_id,a.nombre_asignatura,t.numero) ps)
            ELSE NULL
        END::numeric,


        -- NOTA DE LA EVALUACIÓN SUMATIVA
        CASE
            WHEN public.subject_participates_project(
                v_course_id,
                a.nombre_asignatura
            )
            THEN public.subject_summative_grade(
                p_student_id,
                v_course_id,
                a.nombre_asignatura,
                t.numero
            )
            ELSE NULL
        END::numeric,


        -- PROMEDIO DE EVALUACIÓN FORMATIVA
        public.formative_average(
            p_student_id,
            v_course_id,
            a.nombre_asignatura,
            t.numero
        )::numeric,


        -- NOTA FINAL DEL TRIMESTRE
        public.subject_trimester_grade(
            p_student_id,
            v_course_id,
            a.nombre_asignatura,
            t.numero
        )::numeric


    FROM asignaturas a
    CROSS JOIN trimestres t

    ORDER BY
        a.nombre_asignatura,
        t.numero;

END;

$function$;

commit;
