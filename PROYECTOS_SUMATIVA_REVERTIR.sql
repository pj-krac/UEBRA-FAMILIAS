-- REVERSIÓN DE FUNCIONES: restaura definiciones suministradas. No borra notas/grupos.
begin;
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

    SELECT pg.nota_aporte
    INTO v_aporte
    FROM public.project_grades pg
    WHERE pg.student_id = p_student_id
      AND pg.course_id = p_course_id
      AND pg.trimestre = p_trimestre
      AND lower(trim(pg.asignatura)) =
          lower(trim(p_asignatura))
    LIMIT 1;

    -- El docente todavía no ha registrado su aporte.
    IF v_aporte IS NULL THEN
        RETURN NULL;
    END IF;

    -- Esta función ahora devuelve NULL mientras el proyecto
    -- no esté completo.
    v_promedio_proyecto :=
        public.project_average(
            p_student_id,
            p_trimestre
        );

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

    LEFT JOIN public.project_grades pg
      ON pg.student_id = st.id
     AND pg.course_id = p_course_id
     AND pg.trimestre = p_trimestre
     AND public.normalizar_asignatura(pg.asignatura)
         =
         public.normalizar_asignatura(p_asignatura)

    CROSS JOIN LATERAL public.project_status(
        st.id,
        p_course_id,
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
            THEN public.project_average(
                p_student_id,
                t.numero
            )
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
