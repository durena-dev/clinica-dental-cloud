-- Fictitious development data (demo text in Spanish, codes in English). Rows are referenced by
-- natural keys (email, identification, license number, service name), never by generated ids.
--
-- password_hash is a placeholder, not a valid hash: regenerate it with the API hasher.
-- Logging in with these accounts will not work until then.
--
-- Dates are relative to now(), captured once in seed_context so every statement uses the same
-- instant even if the script crosses midnight. Local dates use the clinic time zone and skip weekends.
-- This seed is meant for a freshly created database: it is not re-runnable (roles are unique).

CREATE TEMP TABLE seed_context AS
SELECT now() AS ts;

-- Business day n counted from the anchor day. The anchor is today when it is a weekday and the
-- clinic has already opened (08:00 local); otherwise it is the last business day before today.
-- This keeps the IN_PROGRESS appointment (08:00 on the anchor day) from ever starting in the future.
CREATE FUNCTION pg_temp.business_day(n integer) RETURNS date
LANGUAGE plpgsql
AS $$
DECLARE
  local_now timestamp := (SELECT ts FROM seed_context) AT TIME ZONE 'America/Costa_Rica';
  d date := local_now::date;
  step integer := CASE WHEN n < 0 THEN -1 ELSE 1 END;
  remaining integer := abs(n);
BEGIN
  IF extract(isodow FROM d) > 5 OR local_now::time < TIME '08:00' THEN
    d := d - 1;
  END IF;
  WHILE extract(isodow FROM d) > 5 LOOP
    d := d - 1;
  END LOOP;
  WHILE remaining > 0 LOOP
    d := d + step;
    IF extract(isodow FROM d) <= 5 THEN
      remaining := remaining - 1;
    END IF;
  END LOOP;
  RETURN d;
END;
$$;

-- ---------- Roles and specialties ----------
INSERT INTO roles (name, description) VALUES
  ('ADMIN', 'Administrador del sistema'),
  ('RECEPTIONIST', 'Recepción y agenda'),
  ('DENTIST', 'Odontólogo'),
  ('PATIENT', 'Paciente con acceso al portal');

INSERT INTO specialties (name, description) VALUES
  ('Odontología general', 'Diagnóstico, limpiezas y tratamientos básicos'),
  ('Endodoncia', 'Tratamientos de conducto');

-- ---------- Users ----------
INSERT INTO users (id_role, full_name, email, phone, password_hash, created_at, updated_at)
SELECT r.id_role, v.full_name, v.email, v.phone, 'NOT_A_REAL_HASH_REGENERATE_WITH_API_HASHER',
       c.ts - interval '60 days', c.ts - interval '60 days'
FROM (VALUES
  ('ADMIN',        'Carlos Vargas',  'admin@clinica.example',          '8000-0001'),
  ('RECEPTIONIST', 'Lucía Prado',    'recepcion@clinica.example',      '8000-0002'),
  ('DENTIST',      'Dra. Ana Mora',  'ana.mora@clinica.example',       '8000-0003'),
  ('DENTIST',      'Dr. Luis Rojas', 'luis.rojas@clinica.example',     '8000-0004'),
  ('DENTIST',      'Dra. Marta Vega', 'marta.vega@clinica.example',    '8000-0005'),
  ('PATIENT',      'Sofía Castro',   'sofia.castro@clinica.example',   '8000-0006'),
  ('PATIENT',      'Mateo Jiménez',  'mateo.jimenez@clinica.example',  '8000-0007')
) AS v (role_name, full_name, email, phone)
JOIN roles r ON r.name = v.role_name
CROSS JOIN seed_context c;

-- ---------- Dentists ----------
INSERT INTO dentists (id_user, id_specialty, license_number, created_at, updated_at)
SELECT u.id_user, s.id_specialty, v.license_number, c.ts - interval '60 days', c.ts - interval '60 days'
FROM (VALUES
  ('ana.mora@clinica.example',   'Odontología general', 'COL-9001'),
  ('luis.rojas@clinica.example', 'Odontología general', 'COL-9002'),
  ('marta.vega@clinica.example', 'Endodoncia',          'COL-9003')
) AS v (email, specialty_name, license_number)
JOIN users u ON u.email = v.email
JOIN specialties s ON s.name = v.specialty_name
CROSS JOIN seed_context c;

-- ---------- Patients (the first two have a portal account) ----------
INSERT INTO patients (id_user, full_name, identification, birth_date, phone, email, emergency_contact, data_consent_at, created_at, updated_at)
SELECT u.id_user, v.full_name, v.identification, v.birth_date, v.phone, v.email, v.emergency_contact,
       c.ts - interval '30 days', c.ts - interval '60 days', c.ts - interval '60 days'
FROM (VALUES
  ('Sofía Castro',    '9-0001-0001', DATE '1990-05-10', '8000-0006', 'sofia.castro@clinica.example',   'María Castro (madre) 8100-0001'),
  ('Mateo Jiménez',   '9-0002-0002', DATE '1985-11-23', '8000-0007', 'mateo.jimenez@clinica.example',  'Elena Jiménez (esposa) 8100-0002'),
  ('Valeria Solís',   '9-0003-0003', DATE '1978-03-02', '8000-0008', 'valeria.solis@clinica.example',  'Jorge Solís (hermano) 8100-0003'),
  ('Andrés Campos',   '9-0004-0004', DATE '2001-08-15', '8000-0009', 'andres.campos@clinica.example',  'Rosa Campos (madre) 8100-0004'),
  ('Daniela Brenes',  '9-0005-0005', DATE '1995-12-30', '8000-0010', 'daniela.brenes@clinica.example', 'Pablo Brenes (padre) 8100-0005')
) AS v (full_name, identification, birth_date, phone, email, emergency_contact)
LEFT JOIN users u ON u.email = v.email
CROSS JOIN seed_context c;

-- ---------- Services ----------
INSERT INTO services (name, description, duration_minutes, price, created_at, updated_at)
SELECT v.name, v.description, v.duration_minutes, v.price, c.ts - interval '60 days', c.ts - interval '60 days'
FROM (VALUES
  ('Limpieza dental',      'Profilaxis y remoción de sarro',          30,  25000.00),
  ('Valoración inicial',   'Primera revisión y plan de tratamiento',  30,  15000.00),
  ('Resina compuesta',     'Restauración con resina',                 60,  40000.00),
  ('Extracción dental',    'Extracción simple',                       45,  35000.00),
  ('Endodoncia',           'Tratamiento de conducto',                 90, 120000.00),
  ('Blanqueamiento dental', 'Sesión de blanqueamiento en consultorio', 60,  90000.00)
) AS v (name, description, duration_minutes, price)
CROSS JOIN seed_context c;

-- Not every dentist offers every service
INSERT INTO dentist_services (id_dentist, id_service)
SELECT d.id_dentist, s.id_service
FROM (VALUES
  ('COL-9001', 'Valoración inicial'), ('COL-9001', 'Limpieza dental'), ('COL-9001', 'Resina compuesta'),
  ('COL-9001', 'Extracción dental'), ('COL-9001', 'Blanqueamiento dental'),
  ('COL-9002', 'Valoración inicial'), ('COL-9002', 'Limpieza dental'), ('COL-9002', 'Resina compuesta'),
  ('COL-9002', 'Blanqueamiento dental'),
  ('COL-9003', 'Valoración inicial'), ('COL-9003', 'Endodoncia'), ('COL-9003', 'Extracción dental')
) AS v (license_number, service_name)
JOIN dentists d ON d.license_number = v.license_number
JOIN services s ON s.name = v.service_name;

-- Monday to Friday (ISO 1-5), clinic local time
INSERT INTO dentist_schedules (id_dentist, day_of_week, start_time, end_time)
SELECT d.id_dentist, dow.day_of_week, t.start_time, t.end_time
FROM dentists d
CROSS JOIN generate_series(1, 5) AS dow (day_of_week)
CROSS JOIN (VALUES (TIME '08:00', TIME '12:00'), (TIME '13:00', TIME '17:00')) AS t (start_time, end_time);

-- One week of vacation, weeks ahead of every seeded appointment
INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at, reason)
SELECT d.id_dentist,
       (pg_temp.business_day(10) + TIME '00:00') AT TIME ZONE 'America/Costa_Rica',
       (pg_temp.business_day(14) + 1 + TIME '00:00') AT TIME ZONE 'America/Costa_Rica',
       'Vacaciones'
FROM dentists d
WHERE d.license_number = 'COL-9001';

-- ---------- Appointments ----------
-- day_offset counts business days from the anchor day (negative = past, 0 = anchor day).
-- All timestamps are computed once here and reused by the statements below.
-- Rules: created_at is at least 2 h before now() and 2 days before the appointment; confirmation 1 day
-- before; the final change (start, completion, no-show, cancellation) is never later than now().
-- last_change_at is the instant of the last log and becomes appointments.updated_at.
CREATE TEMP TABLE seed_appointments (
  ref            integer PRIMARY KEY,
  patient_id     varchar(30),
  license        varchar(30),
  service_name   varchar(120),
  status         varchar(15),
  starts_at      timestamptz,
  ends_at        timestamptz,
  created_at     timestamptz,
  confirmed_at   timestamptz,
  final_at       timestamptz,
  last_change_at timestamptz GENERATED ALWAYS AS (
    COALESCE(final_at, CASE WHEN status = 'CONFIRMED' THEN confirmed_at ELSE created_at END)
  ) STORED,
  id_appointment bigint
);

INSERT INTO seed_appointments (ref, patient_id, license, service_name, status, starts_at, ends_at, created_at, confirmed_at, final_at)
SELECT v.ref, v.patient_id, v.license, v.service_name, v.status, x.starts_at, y.ends_at,
       LEAST(c.ts - interval '2 hours', x.starts_at - interval '2 days'),
       LEAST(c.ts - interval '1 hour', x.starts_at - interval '1 day'),
       CASE v.status
         WHEN 'IN_PROGRESS' THEN LEAST(x.starts_at + interval '5 minutes', c.ts)
         WHEN 'COMPLETED'   THEN y.ends_at
         WHEN 'NO_SHOW'     THEN x.starts_at + interval '15 minutes'
         WHEN 'CANCELLED'   THEN LEAST(c.ts - interval '30 minutes', x.starts_at - interval '12 hours')
       END
FROM (VALUES
  (1,  '9-0001-0001', 'COL-9001', 'Valoración inicial',   -5, '08:00', 'COMPLETED'),
  (2,  '9-0002-0002', 'COL-9001', 'Limpieza dental',      -5, '09:00', 'COMPLETED'),
  (3,  '9-0003-0003', 'COL-9003', 'Endodoncia',           -4, '09:00', 'COMPLETED'),
  (4,  '9-0004-0004', 'COL-9002', 'Resina compuesta',     -3, '13:00', 'COMPLETED'),
  (5,  '9-0005-0005', 'COL-9001', 'Extracción dental',    -3, '10:00', 'COMPLETED'),
  (6,  '9-0001-0001', 'COL-9002', 'Blanqueamiento dental', -2, '14:00', 'COMPLETED'),
  (7,  '9-0002-0002', 'COL-9003', 'Valoración inicial',   -2, '08:00', 'CANCELLED'),
  (8,  '9-0003-0003', 'COL-9001', 'Limpieza dental',      -1, '15:00', 'NO_SHOW'),
  (9,  '9-0004-0004', 'COL-9002', 'Valoración inicial',   -1, '09:30', 'NO_SHOW'),
  (10, '9-0005-0005', 'COL-9003', 'Endodoncia',            0, '08:00', 'IN_PROGRESS'),
  (11, '9-0001-0001', 'COL-9001', 'Limpieza dental',       1, '08:00', 'CONFIRMED'),
  (12, '9-0002-0002', 'COL-9002', 'Resina compuesta',      1, '10:00', 'CONFIRMED'),
  (13, '9-0003-0003', 'COL-9001', 'Valoración inicial',    2, '09:00', 'PENDING'),
  (14, '9-0004-0004', 'COL-9003', 'Valoración inicial',    2, '14:00', 'PENDING'),
  (15, '9-0005-0005', 'COL-9002', 'Blanqueamiento dental', 3, '13:30', 'CONFIRMED'),
  (16, '9-0001-0001', 'COL-9003', 'Extracción dental',     4, '11:00', 'PENDING'),
  (17, '9-0002-0002', 'COL-9001', 'Resina compuesta',      3, '10:00', 'CANCELLED'),
  (18, '9-0003-0003', 'COL-9002', 'Limpieza dental',       5, '16:00', 'PENDING'),
  (19, '9-0004-0004', 'COL-9001', 'Extracción dental',     6, '15:30', 'CONFIRMED'),
  (20, '9-0005-0005', 'COL-9001', 'Valoración inicial',    6, '08:30', 'PENDING')
) AS v (ref, patient_id, license, service_name, day_offset, local_time, status)
JOIN services s ON s.name = v.service_name
CROSS JOIN seed_context c
CROSS JOIN LATERAL (
  SELECT (pg_temp.business_day(v.day_offset) + v.local_time::time) AT TIME ZONE 'America/Costa_Rica' AS starts_at
) x
CROSS JOIN LATERAL (
  SELECT x.starts_at + s.duration_minutes * interval '1 minute' AS ends_at
) y;

WITH inserted AS (
  INSERT INTO appointments (id_patient, id_dentist, id_service, starts_at, ends_at, status, price_snapshot, created_at, updated_at)
  SELECT p.id_patient, d.id_dentist, s.id_service, sa.starts_at, sa.ends_at, sa.status, s.price,
         sa.created_at, sa.last_change_at
  FROM seed_appointments sa
  JOIN patients p ON p.identification = sa.patient_id
  JOIN dentists d ON d.license_number = sa.license
  JOIN services s ON s.name = sa.service_name
  ORDER BY sa.ref
  RETURNING id_appointment, id_dentist, starts_at
)
UPDATE seed_appointments sa
SET id_appointment = i.id_appointment
FROM inserted i
JOIN dentists d ON d.id_dentist = i.id_dentist
WHERE d.license_number = sa.license
  AND i.starts_at = sa.starts_at;

-- Status history. Creation and confirmation by reception; start, completion and no-show by the dentist.
INSERT INTO appointment_logs (id_appointment, changed_by, previous_status, new_status, changed_at, remarks)
SELECT sa.id_appointment,
       CASE t.actor WHEN 'RECEPTION' THEN rec.id_user ELSE d.id_user END,
       t.previous_status, t.new_status, t.changed_at, t.remarks
FROM seed_appointments sa
JOIN dentists d ON d.license_number = sa.license
CROSS JOIN (SELECT id_user FROM users WHERE email = 'recepcion@clinica.example') rec
CROSS JOIN LATERAL (VALUES
  (1, 'RECEPTION', NULL::varchar,   'PENDING',     sa.created_at,
      'Cita creada', true),
  (2, 'RECEPTION', 'PENDING',       'CONFIRMED',   sa.confirmed_at,
      'Confirmada con el paciente', sa.status IN ('CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'NO_SHOW')),
  (3, 'DENTIST',   'CONFIRMED',     'IN_PROGRESS',
      CASE sa.status WHEN 'IN_PROGRESS' THEN sa.final_at ELSE sa.starts_at END,
      'El paciente llegó a la consulta', sa.status IN ('IN_PROGRESS', 'COMPLETED')),
  (4, 'DENTIST',   'IN_PROGRESS',   'COMPLETED',   sa.final_at,
      'Expediente clínico guardado', sa.status = 'COMPLETED'),
  (5, 'DENTIST',   'CONFIRMED',     'NO_SHOW',     sa.final_at,
      'El paciente no se presentó', sa.status = 'NO_SHOW'),
  (6, 'RECEPTION', 'PENDING',       'CANCELLED',   sa.final_at,
      'Cancelada a solicitud del paciente', sa.status = 'CANCELLED')
) AS t (seq, actor, previous_status, new_status, changed_at, remarks, applies)
WHERE t.applies
ORDER BY sa.ref, t.seq;

-- ---------- Medical records (completed appointments only) ----------
-- Saved in the same transaction as the COMPLETED log, so same instant.
INSERT INTO medical_records (id_appointment, symptoms, physical_exam, diagnosis, treatment_plan, prescriptions, clinical_notes, created_at, updated_at)
SELECT sa.id_appointment, v.symptoms, v.physical_exam, v.diagnosis, v.treatment_plan, v.prescriptions, v.clinical_notes,
       sa.final_at, sa.final_at
FROM (VALUES
  (1, 'Sensibilidad al frío',   'Sin caries visibles; leve inflamación de encías',  'Gingivitis',                 'Limpieza y mejora de la técnica de cepillado', NULL::text,           'Control en 6 meses'),
  (2, NULL::text,               'Placa y sarro en incisivos inferiores',            'Cálculo dental',             'Remoción de sarro completada en la sesión',    NULL::text,           NULL::text),
  (3, 'Dolor persistente',      'Sensibilidad a la percusión en la pieza 36',       'Pulpitis irreversible',      'Endodoncia en una sesión y corona',            'Ibuprofeno 400 mg',  'Programar la corona'),
  (4, 'Molestia al masticar',   'Caries oclusal en la pieza 46',                    'Caries moderada',            'Restauración con resina colocada',             NULL::text,           NULL::text),
  (5, 'Dolor al morder',        'Pieza 48 fracturada, sin posibilidad de restaurar', 'Pieza no restaurable',      'Extracción simple realizada',                  'Amoxicilina 500 mg', 'Revisar cicatrización en una semana'),
  (6, NULL::text,               'Encías sanas, leve pigmentación superficial',      'Pigmentación extrínseca',    'Sesión de blanqueamiento completada',          NULL::text,           'Evitar bebidas oscuras por 48 horas')
) AS v (ref, symptoms, physical_exam, diagnosis, treatment_plan, prescriptions, clinical_notes)
JOIN seed_appointments sa ON sa.ref = v.ref;

-- ---------- Notifications ----------
-- The reminder (starts_at - 24 h) always exists: every appointment is created more than 24 h ahead.
-- It is SENT once its time has passed (or before the cancellation, if the appointment was cancelled)
-- and PENDING while it is still ahead. Only a cancelled appointment whose reminder had not gone out yet
-- leaves it CANCELLED.
INSERT INTO notifications (id_appointment, type, recipient, status, retry_count, scheduled_for, sent_at, created_at)
SELECT n.id_appointment, n.type, n.recipient, n.status, n.retry_count, n.scheduled_for, n.sent_at, n.created_at
FROM (
  SELECT sa.id_appointment, 'CONFIRMATION' AS type, p.email AS recipient,
         CASE sa.ref WHEN 14 THEN 'FAILED' WHEN 20 THEN 'PENDING' ELSE 'SENT' END AS status,
         CASE sa.ref WHEN 14 THEN 2 ELSE 0 END AS retry_count,
         sa.created_at AS scheduled_for,
         CASE WHEN sa.ref IN (14, 20) THEN NULL ELSE sa.created_at + interval '1 minute' END AS sent_at,
         sa.created_at AS created_at
  FROM seed_appointments sa
  JOIN patients p ON p.identification = sa.patient_id
  UNION ALL
  SELECT sa.id_appointment, 'REMINDER', p.email,
         CASE WHEN sa.starts_at - interval '24 hours' <= h.horizon THEN 'SENT'
              WHEN sa.status = 'CANCELLED' THEN 'CANCELLED'
              ELSE 'PENDING' END,
         0,
         sa.starts_at - interval '24 hours',
         CASE WHEN sa.starts_at - interval '24 hours' <= h.horizon
              THEN LEAST(sa.starts_at - interval '24 hours' + interval '1 minute', h.horizon) END,
         sa.created_at
  FROM seed_appointments sa
  JOIN patients p ON p.identification = sa.patient_id
  CROSS JOIN seed_context c
  CROSS JOIN LATERAL (SELECT CASE WHEN sa.status = 'CANCELLED' THEN sa.final_at ELSE c.ts END AS horizon) h
  UNION ALL
  SELECT sa.id_appointment, 'CANCELLATION', p.email, 'SENT', 0,
         sa.final_at, sa.final_at + interval '1 minute', sa.final_at
  FROM seed_appointments sa
  JOIN patients p ON p.identification = sa.patient_id
  WHERE sa.status = 'CANCELLED'
) AS n
ORDER BY n.id_appointment, n.type;

DROP FUNCTION pg_temp.business_day(integer);
DROP TABLE seed_appointments;
DROP TABLE seed_context;
