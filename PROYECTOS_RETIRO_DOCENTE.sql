-- RETIRO DE UN PROYECTO. Aplicar después de las migraciones de proyectos anteriores.
-- No ejecutado. Conserva project_grades y registro de la configuración anterior.
begin;
create table if not exists public.flexible_sumative_withdrawals(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null,course_id uuid not null,anio_lectivo text not null,
 trimestre smallint not null,asignatura text not null,
 actor_id uuid not null,created_at timestamptz not null default now(),
 configuracion_anterior jsonb not null
);
alter table public.flexible_sumative_withdrawals enable row level security;
revoke all on public.flexible_sumative_withdrawals from anon,authenticated;

create or replace function public.teacher_withdraw_sumative_project(
 p_course_id uuid,p_asignatura text,p_trimestre smallint,p_project_id uuid
) returns void language plpgsql security definer set search_path='' as $$
declare v_year text;v_project public.flexible_sumative_projects%rowtype;
 v_before jsonb;v_remaining integer;v_accepted boolean;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and activo)
    or not public.can_manage_grade_assignment(p_course_id,p_asignatura) then
    raise exception 'Acceso no autorizado';
 end if;
 select i.anio_lectivo into v_year from public.institution_settings i where i.id=1;
 if v_year is null or p_trimestre is null or p_trimestre not between 1 and 3 or p_project_id is null then raise exception 'Selección inválida';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_course_id::text||v_year||p_trimestre::text,0));
 if exists(select 1 from public.flexible_sumative_activation a where a.course_id=p_course_id and a.trimestre=p_trimestre) then
    raise exception 'El cálculo ya está activado. Solicite revisión administrativa; no se puede cambiar el grupo desde aquí';
 end if;
 select p.* into v_project from public.flexible_sumative_projects p
 where p.id=p_project_id and p.course_id=p_course_id and p.anio_lectivo=v_year and p.trimestre=p_trimestre for update;
 if not found then raise exception 'Proyecto no encontrado';end if;
 if not exists(select 1 from public.flexible_sumative_members m where m.project_id=p_project_id and public.normalizar_asignatura(m.asignatura)=public.normalizar_asignatura(p_asignatura)) then raise exception 'Su materia no pertenece a este proyecto';end if;
 select jsonb_build_object('proyecto',to_jsonb(v_project),'participantes',coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb)) into v_before from public.flexible_sumative_members m where m.project_id=p_project_id;
 insert into public.flexible_sumative_withdrawals(project_id,course_id,anio_lectivo,trimestre,asignatura,actor_id,configuracion_anterior)
 values(p_project_id,p_course_id,v_year,p_trimestre,p_asignatura,auth.uid(),v_before);
 -- Solo libera la asignatura del docente. No elimina aportes de calificaciones.
 delete from public.flexible_sumative_members m where m.project_id=p_project_id
 and public.normalizar_asignatura(m.asignatura)=public.normalizar_asignatura(p_asignatura);
 select count(*),coalesce(bool_and(m.aceptado),false) into v_remaining,v_accepted from public.flexible_sumative_members m where m.project_id=p_project_id;
 if v_remaining=0 then
    -- Grupo vacío archivado en withdrawals; no dejar una reserva vacía que bloquee activación.
    delete from public.flexible_sumative_projects where id=p_project_id;
 elsif v_remaining=1 then
    update public.flexible_sumative_projects set confirmado=v_accepted where id=p_project_id;
 else
    -- Cambió la composición: las materias restantes deben confirmar de nuevo.
    update public.flexible_sumative_members set aceptado=false where project_id=p_project_id;
    update public.flexible_sumative_projects set confirmado=false where id=p_project_id;
 end if;
end;
$$;
revoke all on function public.teacher_withdraw_sumative_project(uuid,text,smallint,uuid) from public,anon;
grant execute on function public.teacher_withdraw_sumative_project(uuid,text,smallint,uuid) to authenticated;
commit;
