-- =====================================================
-- MM Ingeniería · Recordatorios por EMAIL (8 etapas)
-- + aviso semanal del horario (1 hora antes de cada clase)
--
-- Ejecutar TODO este archivo en: Supabase → SQL Editor → Run
--
-- PASO PREVIO (una sola vez, guarda la API key en Vault):
--   select vault.create_secret(
--     'TU_API_KEY_DE_RESEND',
--     'resend_api_key',
--     'API key de Resend para recordatorios por email'
--   );
--
-- Requisitos: haber ejecutado supabase/schema.sql (tablas creadas)
-- =====================================================

-- ---------- EXTENSIONES ----------
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------- COLUMNA DE CONTROL DE ETAPAS (tareas) ----------
-- Guarda la última etapa de aviso enviada por email para no repetir.
-- Etapas: 7d (1 semana) → 3d → 1d → 3h → 1h → 30m → 15m → 5m

alter table tareas add column if not exists ultimo_aviso text;

-- ---------- TABLA DE AVISOS DEL HORARIO ----------
-- Evita enviar el email de una clase más de una vez el mismo día.

create table if not exists avisos_horario (
  dia   text not null,
  hora  int  not null,
  fecha date not null,
  primary key (dia, hora, fecha)
);

-- =====================================================
-- FUNCIÓN 1: recordatorios de TAREAS en 8 etapas
-- =====================================================

create or replace function enviar_recordatorios_email()
returns void
language plpgsql
as $$
declare
  t record;
  rem_min int;
  aviso text;
  idx_aviso int := 0;
  idx_ultimo int := 0;
  etiqueta text;
  api_key text;
begin
  select decrypted_secret into api_key
  from vault.decrypted_secrets
  where name = 'resend_api_key'
  limit 1;

  if api_key is null or api_key = '' then
    raise notice 'Falta el secreto resend_api_key en Vault';
    return;
  end if;

  for t in
    select * from tareas where hecha = false
  loop
    rem_min := floor(extract(epoch from ((t.fecha + t.hora) - (now() at time zone 'America/Lima')::timestamp)) / 60);

    if rem_min > 0 then
      if rem_min <= 5 then aviso := '5m';  etiqueta := 'faltan 5 min';
      elsif rem_min <= 15 then aviso := '15m'; etiqueta := 'faltan 15 min';
      elsif rem_min <= 30 then aviso := '30m'; etiqueta := 'faltan 30 min';
      elsif rem_min <= 60 then aviso := '1h';  etiqueta := 'falta 1 hora';
      elsif rem_min <= 180 then aviso := '3h'; etiqueta := 'faltan 3 horas';
      elsif rem_min <= 1440 then aviso := '1d'; etiqueta := 'falta 1 día';
      elsif rem_min <= 4320 then aviso := '3d'; etiqueta := 'faltan 3 días';
      elsif rem_min <= 10080 then aviso := '7d'; etiqueta := 'falta 1 semana';
      else aviso := null;
      end if;

      if aviso is not null then
        idx_aviso := case aviso
          when '7d' then 1 when '3d' then 2 when '1d' then 3 when '3h' then 4
          when '1h' then 5 when '30m' then 6 when '15m' then 7 when '5m' then 8
          else 0 end;

        idx_ultimo := case t.ultimo_aviso
          when '7d' then 1 when '3d' then 2 when '1d' then 3 when '3h' then 4
          when '1h' then 5 when '30m' then 6 when '15m' then 7 when '5m' then 8
          else 0 end;

        if idx_aviso > idx_ultimo then
          perform net.http_post(
            url := 'https://api.resend.com/emails',
            headers := jsonb_build_object(
              'Authorization', 'Bearer ' || api_key,
              'Content-Type', 'application/json'
            ),
            body := jsonb_build_object(
              'from', 'Recordatorios MM <onboarding@resend.dev>',
              'to', jsonb_build_array('marcoalexsandiomaytanhuaraca@gmail.com'),
              'subject', '⏰ ' || etiqueta || ': ' || t.titulo,
              'html',
                '<h2>⏰ ' || t.titulo || '</h2>'
                || '<p style="font-size:16px"><strong>⏳ ' || etiqueta || '.</strong></p>'
                || '<p><strong>📅 Fecha:</strong> ' || to_char(t.fecha, 'DD/MM/YYYY') || '</p>'
                || '<p><strong>🕒 Hora:</strong> ' || to_char(t.hora, 'HH24:MI') || '</p>'
                || case
                     when t.nota is not null and t.nota <> '' then '<p><strong>📝 Nota:</strong> ' || t.nota || '</p>'
                     else ''
                   end
                || '<hr/><p style="color:#777;font-size:12px">Recordatorio automático · MM Ingeniería</p>'
            )
          );

          update tareas set ultimo_aviso = aviso where id = t.id;
        end if;
      end if;
    end if;
  end loop;
end;
$$;

-- =====================================================
-- FUNCIÓN 2: aviso del HORARIO 1 hora antes de la clase
-- de hoy, cada semana
-- =====================================================

create or replace function enviar_recordatorios_horario()
returns void
language plpgsql
as $$
declare
  r record;
  ahora timestamp;
  hoy date;
  nombre_dia text;
  clase timestamp;
  api_key text;
begin
  select decrypted_secret into api_key
  from vault.decrypted_secrets
  where name = 'resend_api_key'
  limit 1;

  if api_key is null or api_key = '' then
    raise notice 'Falta el secreto resend_api_key en Vault';
    return;
  end if;

  ahora := (now() at time zone 'America/Lima')::timestamp;
  hoy := ahora::date;
  nombre_dia := case extract(dow from ahora)
    when 0 then 'Domingo' when 1 then 'Lunes' when 2 then 'Martes'
    when 3 then 'Miércoles' when 4 then 'Jueves' when 5 then 'Viernes'
    when 6 then 'Sábado' end;

  for r in
    select * from horario
    where dia = nombre_dia
      and contenido is not null and contenido <> ''
  loop
    clase := hoy + make_time(r.hora, 0, 0);

    if ahora >= clase - interval '1 hour' and ahora < clase then
      if not exists (
        select 1 from avisos_horario
        where dia = r.dia and hora = r.hora and fecha = hoy
      ) then
        perform net.http_post(
          url := 'https://api.resend.com/emails',
          headers := jsonb_build_object(
            'Authorization', 'Bearer ' || api_key,
            'Content-Type', 'application/json'
          ),
          body := jsonb_build_object(
            'from', 'Recordatorios MM <onboarding@resend.dev>',
            'to', jsonb_build_array('marcoalexsandiomaytanhuaraca@gmail.com'),
            'subject', '⏰ En 1 hora tienes: ' || r.contenido,
            'html',
              '<h2>⏰ ' || r.contenido || '</h2>'
              || '<p><strong>⏳ Falta 1 hora para tu clase.</strong></p>'
              || '<p><strong>📅 Hoy:</strong> ' || r.dia || '</p>'
              || '<p><strong>🕒 Hora:</strong> ' || lpad(r.hora::text, 2, '0') || ':00</p>'
              || '<hr/><p style="color:#777;font-size:12px">Recordatorio semanal de tu horario · MM Ingeniería</p>'
          )
        );

        insert into avisos_horario (dia, hora, fecha) values (r.dia, r.hora, hoy);
      end if;
    end if;
  end loop;
end;
$$;

-- =====================================================
-- FUNCIÓN 3: ejecuta ambos recordatorios
-- =====================================================

create or replace function ejecutar_recordatorios()
returns void
language plpgsql
as $$
begin
  perform enviar_recordatorios_email();
  perform enviar_recordatorios_horario();
end;
$$;

-- ---------- PROGRAMAR CADA MINUTO ----------
-- Si el proyecto de Supabase queda inactivo 7 días (plan gratis),
-- se pausa y los recordatorios se reanudan al volver a visitar la web.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'recordatorios-email-cada-minuto') then
    perform cron.unschedule('recordatorios-email-cada-minuto');
  end if;
end $$;

select cron.schedule('recordatorios-email-cada-minuto', '* * * * *', $$select ejecutar_recordatorios();$$);
