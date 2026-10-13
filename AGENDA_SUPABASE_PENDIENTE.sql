-- AGENDA ESCOLAR: PROPUESTA PENDIENTE DE APROBACIÓN. NO EJECUTADA.
-- Requiere la función family_student_school_calendar ya aprobada.
begin;
create table if not exists public.school_agenda_events (
 id uuid primary key default gen_random_uuid(),
 fecha date not null,
 tipo text not null check(tipo in ('FERIADO','PRUEBA','LECCION','PROYECTO','REUNION','ACTIVIDAD')),
 titulo text not null check(length(btrim(titulo)) between 1 and 180),
 observacion text not null default '' check(length(observacion)<=2000),
 asignatura text not null default '' check(length(asignatura)<=120),
 jornada text check(jornada in ('MATUTINA','VESPERTINA')),
 course_id uuid references public.courses(id),
 sin_clases boolean not null default false,
 publicar_familias boolean not null default false,
 activo boolean not null default true,
 created_at timestamptz not null default now(),
 check(course_id is null or jornada is null)
);
alter table public.school_agenda_events enable row level security;
create policy agenda_admin on public.school_agenda_events for all to authenticated
 using(public.is_admin() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.activo is true))
 with check(public.is_admin() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.activo is true));
revoke all on public.school_agenda_events from anon, authenticated;
grant select,insert,update on public.school_agenda_events to authenticated;
create index if not exists school_agenda_events_fecha_idx on public.school_agenda_events(fecha) where activo and publicar_familias;
create or replace function public.family_student_agenda(p_student_id uuid,p_from date,p_to date)
returns table(fecha date,tipo text,titulo text,observacion text,asignatura text,jornada text,curso text,sin_clases boolean)
language plpgsql stable security definer set search_path='' as $$
declare v_course uuid; v_shift text; v_name text;
begin
 if auth.uid() is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>730 then raise exception 'Consulta no autorizada o rango inválido'; end if;
 select s.course_id,c.jornada,c.nombre into v_course,v_shift,v_name
 from public.students s join public.courses c on c.id=s.course_id
 where s.id=p_student_id and exists(
 select 1 from public.student_family sf join public.family_members fm on fm.id=sf.family_member_id
 where sf.student_id=s.id and sf.activo is true and sf.es_representante is true
 and fm.activo is true and fm.must_change_password is false and fm.auth_user_id=auth.uid());
 if not found then raise exception 'Acceso no autorizado'; end if;
 return query
 select x.fecha,'FECHA_SIN_CLASE'::text,x.motivo,''::text,''::text,x.jornada,''::text,true
 from public.family_student_school_calendar(p_student_id,p_from,p_to) x
 union all
 select e.fecha,e.tipo,e.titulo,e.observacion,e.asignatura,e.jornada,
 case when e.course_id is not null then v_name else '' end,e.sin_clases
 from public.school_agenda_events e
 where e.activo and e.publicar_familias and e.fecha between p_from and p_to
 and (e.course_id=v_course or (e.course_id is null and (e.jornada is null or e.jornada=v_shift)))
 order by 1,3;
end;
$$;
revoke all on function public.family_student_agenda(uuid,date,date) from public,anon;
grant execute on function public.family_student_agenda(uuid,date,date) to authenticated;
commit;
-- No inserta ni publica eventos ni modifica las excepciones de asistencia.
