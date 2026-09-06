-- =====================================================
-- MM Ingeniería · Recordatorios por EMAIL al celular
-- Ejecutar TODO este archivo en: Supabase → SQL Editor → Run
--
-- IMPORTANTE: antes de ejecutar, reemplaza TU_API_KEY_RESEND
-- por tu API key de Resend (resend.com → API Keys, empieza con re_).
--
-- Requisitos previos:
--   - Haber ejecutado supabase/schema.sql (tablas creadas)
--   - Cuenta de Resend con la API key lista
-- =====================================================

-- ---------- EXTENSIONES ----------
-- pg_cron: tarea programada que corre cada minuto en el servidor
-- pg_net : para hacer peticiones HTTP (enviar el email vía Resend)

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------- COLUMNA DE CONTROL ----------
-- Marca las tareas que ya fueron avisadas por email para no repetir

alter table tareas add column if not exists notificada boolean not null default false;

-- ---------- FUNCIÓN QUE ENVÍA LOS RECORDATORIOS ----------

create or replace function enviar_recordatorios_email()
returns void
language plpgsql
as $$
declare
  t record;
  mins int;
begin
  for t in
    select *
    from tareas
    where hecha = false
      and notificada = false
      and (fecha + hora) > ((now() at time zone 'America/Lima')::timestamp)
      and (fecha + hora) <= ((now() at time zone 'America/Lima')::timestamp + interval '60 minutes')
  loop
    mins := greatest(1, floor(extract(epoch from ((t.fecha + t.hora) - (now() at time zone 'America/Lima')::timestamp)) / 60));

    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer TU_API_KEY_RESEND',
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'from', 'Recordatorios MM <onboarding@resend.dev>',
        'to', jsonb_build_array('marcoalexsandiomaytanhuaraca@gmail.com'),
        'subject', '⏰ Recordatorio: ' || t.titulo,
        'html',
          '<h2>⏰ ' || t.titulo || '</h2>'
          || '<p><strong>📅 Fecha:</strong> ' || to_char(t.fecha, 'DD/MM/YYYY') || '</p>'
          || '<p><strong>🕒 Hora:</strong> ' || to_char(t.hora, 'HH24:MI') || '</p>'
          || '<p><strong>⏳ Empieza en:</strong> ' || mins || ' minutos</p>'
          || case
               when t.nota is not null and t.nota <> '' then '<p><strong>📝 Nota:</strong> ' || t.nota || '</p>'
               else ''
             end
          || '<hr/><p style="color:#777;font-size:12px">Recordatorio automático · MM Ingeniería</p>'
      )
    );

    update tareas set notificada = true where id = t.id;
  end loop;
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

select cron.schedule('recordatorios-email-cada-minuto', '* * * * *', $$select enviar_recordatorios_email();$$);
