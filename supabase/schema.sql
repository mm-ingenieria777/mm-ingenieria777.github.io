-- =====================================================
-- MM Ingeniería · Backend de la página Persona
-- Ejecutar TODO este archivo en: Supabase → SQL Editor → Run
-- =====================================================

-- ---------- TABLAS ----------

create table if not exists tareas (
  id      uuid primary key default gen_random_uuid(),
  titulo  text not null,
  nota    text,
  fecha   date not null,
  hora    time not null,
  hecha   boolean not null default false,
  creada  timestamptz not null default now()
);

create table if not exists horario (
  dia       text not null,
  hora      int  not null,
  contenido text not null default '',
  color     text,
  primary key (dia, hora)
);

-- Si la tabla horario ya existía sin la columna color, ejecuta:
-- alter table horario add column if not exists color text;

-- ---------- SEGURIDAD (RLS) ----------
-- Uso personal sin login: políticas abiertas para el rol anon.
-- La anon key estará visible en la página; cualquiera con tu
-- URL de proyecto podría ver/editar estos datos. Si algún día
-- quieres protegerlos, configura Supabase Auth y políticas por usuario.

alter table tareas  enable row level security;
alter table horario enable row level security;

drop policy if exists anon_tareas_all  on tareas;
drop policy if exists anon_horario_all on horario;

create policy anon_tareas_all
  on tareas for all
  to anon
  using (true)
  with check (true);

create policy anon_horario_all
  on horario for all
  to anon
  using (true)
  with check (true);

-- ---------- PERMISOS PARA EL ROL anon ----------
-- En proyectos nuevos de Supabase, el rol anon no tiene privilegios
-- por defecto sobre las tablas. Los otorgamos explícitamente.

grant usage on schema public to anon;
grant select, insert, update, delete on all tables in schema public to anon;

-- ---------- DATOS DE EJEMPLO (HORARIO) ----------

insert into horario (dia, hora, contenido) values
  ('Lunes',      8,  'Cálculo Numérico'),
  ('Lunes',      10, 'Mecánica de Fluidos'),
  ('Martes',     9,  'Estructuras I'),
  ('Martes',     15, 'Taller BIM / Revit'),
  ('Miércoles',  8,  'Cálculo Numérico'),
  ('Miércoles',  11, 'Estudio personal'),
  ('Jueves',     9,  'Estructuras I'),
  ('Viernes',    8,  'Mecánica de Fluidos'),
  ('Viernes',    14, 'Normativa RNE'),
  ('Sábado',     10, 'Práctica Revit / Navisworks'),
  ('Domingo',    9,  'Repaso semanal')
on conflict (dia, hora) do nothing;
