-- ELECCIÓN POR DOCENTES: aplicar después de PROYECTOS_SUMATIVA_IMPLEMENTAR.sql.
-- Pendiente de aprobación. No ejecutado. No cambia aportes ni cierre de año.
begin;
alter table public.flexible_sumative_members add column if not exists aceptado boolean not null default true;

create or replace function public.teacher_sumative_choice(p_course_id uuid,p_asignatura text,p_trimestre smallint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_year text;v_subjects jsonb;v_group jsonb;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and activo) or not public.can_manage_grade_assignment(p_course_id,p_asignatura) or not public.subject_participates_project(p_course_id,p_asignatura) then raise exception 'Acceso no autorizado'; end if;
 if p_trimestre is null or p_trimestre not between 1 and 3 then raise exception 'Trimestre inválido';end if;
 select i.anio_lectivo into v_year from public.institution_settings i where i.id=1;
 if v_year is null or length(btrim(v_year))<4 then raise exception 'Configure el año lectivo institucional';end if;
 select coalesce(jsonb_agg(jsonb_build_object('nombre',s.nombre,'clave',s.clave) order by s.nombre),'[]'::jsonb) into v_subjects
 from (select public.normalizar_asignatura(sc.asignatura) clave,min(sc.asignatura) nombre from public.schedules sc where sc.course_id=p_course_id and sc.activo and public.subject_participates_project(p_course_id,sc.asignatura) group by public.normalizar_asignatura(sc.asignatura)) s;
 select jsonb_build_object('id',p.id,'nombre',p.nombre,'confirmado',p.confirmado,'mi_confirmacion',own.aceptado,'participantes',(select jsonb_agg(jsonb_build_object('nombre',m.asignatura,'aceptado',m.aceptado) order by m.asignatura) from public.flexible_sumative_members m where m.project_id=p.id)) into v_group
 from public.flexible_sumative_projects p join public.flexible_sumative_members own on own.project_id=p.id
 where p.course_id=p_course_id and p.anio_lectivo=v_year and p.trimestre=p_trimestre and public.normalizar_asignatura(own.asignatura)=public.normalizar_asignatura(p_asignatura);
 return jsonb_build_object('anio_lectivo',v_year,'asignatura_clave',public.normalizar_asignatura(p_asignatura),'asignaturas',v_subjects,'grupo',v_group,'activado',exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre));
end;
$$;

create or replace function public.teacher_propose_sumative_project(p_course_id uuid,p_asignatura text,p_trimestre smallint,p_nombre text,p_asignaturas text[])
returns uuid language plpgsql security definer set search_path='' as $$
declare v_year text;v_id uuid;v_subject text;v_count integer;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and activo) or not public.can_manage_grade_assignment(p_course_id,p_asignatura) or not public.subject_participates_project(p_course_id,p_asignatura) then raise exception 'Acceso no autorizado';end if;
 select i.anio_lectivo into v_year from public.institution_settings i where i.id=1;
 if v_year is null or length(btrim(v_year))<4 or p_trimestre is null or p_trimestre not between 1 and 3 or p_nombre is null or length(btrim(p_nombre)) not between 1 and 180 then raise exception 'Datos inválidos';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_course_id::text||v_year||p_trimestre::text,0));
 if exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre) then raise exception 'El período ya está activado y bloqueado';end if;
 select count(distinct public.normalizar_asignatura(x)) into v_count from unnest(p_asignaturas) x where nullif(btrim(x),'') is not null;
 if v_count=0 or v_count<>cardinality(p_asignaturas) or not exists(select 1 from unnest(p_asignaturas) x where public.normalizar_asignatura(x)=public.normalizar_asignatura(p_asignatura)) then raise exception 'Incluya su materia y seleccione participantes únicos';end if;
 foreach v_subject in array p_asignaturas loop
 if not public.subject_participates_project(p_course_id,v_subject) or not exists(select 1 from public.schedules s where s.course_id=p_course_id and s.activo and public.normalizar_asignatura(s.asignatura)=public.normalizar_asignatura(v_subject)) then raise exception 'Materia inválida: %',v_subject;end if;
 if exists(select 1 from public.flexible_sumative_members m where m.course_id=p_course_id and m.anio_lectivo=v_year and m.trimestre=p_trimestre and public.normalizar_asignatura(m.asignatura)=public.normalizar_asignatura(v_subject)) then raise exception 'La asignatura % ya pertenece a un proyecto; revise la invitación o coordine con administración',v_subject;end if;
 end loop;
 insert into public.flexible_sumative_projects(course_id,anio_lectivo,trimestre,nombre,confirmado) values(p_course_id,v_year,p_trimestre,btrim(p_nombre),v_count=1) returning id into v_id;
 insert into public.flexible_sumative_members(project_id,course_id,anio_lectivo,trimestre,asignatura,aceptado)
 select v_id,p_course_id,v_year,p_trimestre,x,public.normalizar_asignatura(x)=public.normalizar_asignatura(p_asignatura) from unnest(p_asignaturas) x;
 return v_id;
end;
$$;

create or replace function public.teacher_accept_sumative_project(p_course_id uuid,p_asignatura text,p_trimestre smallint,p_project_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_year text;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and activo) or not public.can_manage_grade_assignment(p_course_id,p_asignatura) then raise exception 'Acceso no autorizado';end if;
 select i.anio_lectivo into v_year from public.institution_settings i where i.id=1;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_course_id::text||v_year||p_trimestre::text,0));
 if exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre) then raise exception 'Período bloqueado';end if;
 if not exists(select 1 from public.flexible_sumative_projects p where p.id=p_project_id and p.course_id=p_course_id and p.anio_lectivo=v_year and p.trimestre=p_trimestre and not p.confirmado) then raise exception 'Invitación inválida';end if;
 update public.flexible_sumative_members set aceptado=true where project_id=p_project_id and public.normalizar_asignatura(asignatura)=public.normalizar_asignatura(p_asignatura);
 if not found then raise exception 'No es participante';end if;
 if not exists(select 1 from public.flexible_sumative_members where project_id=p_project_id and not aceptado) then update public.flexible_sumative_projects set confirmado=true where id=p_project_id;end if;
end;
$$;
revoke all on function public.teacher_sumative_choice(uuid,text,smallint) from public,anon;
revoke all on function public.teacher_propose_sumative_project(uuid,text,smallint,text,text[]) from public,anon;
revoke all on function public.teacher_accept_sumative_project(uuid,text,smallint,uuid) from public,anon;
grant execute on function public.teacher_sumative_choice(uuid,text,smallint) to authenticated;
grant execute on function public.teacher_propose_sumative_project(uuid,text,smallint,text,text[]) to authenticated;
grant execute on function public.teacher_accept_sumative_project(uuid,text,smallint,uuid) to authenticated;
commit;
