-- PROPUESTA PARA REVISIÓN Y APROBACIÓN. NO EJECUTADA.
-- Confirmar tipos/columnas, políticas y propietario de función en el servidor.
-- publicar_familias=false evita publicar automáticamente motivos existentes.
begin;
alter table public.school_calendar_exceptions
  add column if not exists publicar_familias boolean not null default false;
create or replace function public.family_student_school_calendar(
  p_student_id uuid, p_from date, p_to date
) returns table(fecha date, motivo text, jornada text)
language plpgsql stable security definer set search_path = '' as $$
declare v_jornada text;
begin
  if auth.uid() is null then raise exception 'Acceso no autorizado'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to-p_from > 730 then
    raise exception 'Rango de fechas inválido (máximo 730 días)';
  end if;
  select c.jornada into v_jornada
  from public.students s
  join public.courses c on c.id=s.course_id
  where s.id=p_student_id and exists (
    select 1 from public.student_family sf
    join public.family_members fm on fm.id=sf.family_member_id
    where sf.student_id=s.id and sf.activo is true
      and sf.es_representante is true and fm.activo is true
      and fm.auth_user_id=auth.uid()
      and fm.must_change_password is false
  );
  if not found or v_jornada is null then raise exception 'Acceso no autorizado'; end if;
  return query select ce.fecha, ce.motivo::text, ce.jornada::text
  from public.school_calendar_exceptions ce
  where ce.activo is true and ce.publicar_familias is true
    and ce.fecha between p_from and p_to
    and (nullif(btrim(ce.jornada),'') is null or ce.jornada=v_jornada)
  order by ce.fecha, ce.motivo;
end;
$$;
revoke all on function public.family_student_school_calendar(uuid,date,date) from public, anon;
grant execute on function public.family_student_school_calendar(uuid,date,date) to authenticated;
commit;
-- Ninguna fecha se publica mediante este script.
-- Publicar fechas específicas requiere aprobación y actualización administrativa
-- de publicar_familias=true. No conceder edición a representantes.
