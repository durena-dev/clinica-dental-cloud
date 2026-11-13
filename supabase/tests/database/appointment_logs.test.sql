BEGIN;
SELECT plan(4);

INSERT INTO roles (name) VALUES ('DENTIST') ON CONFLICT (name) DO NOTHING;
INSERT INTO users (id_role, full_name, email, password_hash)
SELECT id_role, 'Test Dentist A', 'test.dentist.a@example.test', 'hash' FROM roles WHERE name = 'DENTIST';
INSERT INTO specialties (name) VALUES ('TEST-General');
INSERT INTO dentists (id_user, id_specialty, license_number)
SELECT (SELECT id_user FROM users WHERE email = 'test.dentist.a@example.test'),
       (SELECT id_specialty FROM specialties WHERE name = 'TEST-General'), 'TEST-LIC-A';
INSERT INTO patients (full_name, identification) VALUES ('Test Patient One', 'TEST-ID-001');
INSERT INTO services (name, duration_minutes, price) VALUES ('TEST-Cleaning', 60, 50);
INSERT INTO dentist_services (id_dentist, id_service)
SELECT (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A'),
       (SELECT id_service FROM services WHERE name = 'TEST-Cleaning');
INSERT INTO appointments (id_patient, id_dentist, id_service, starts_at, ends_at, price_snapshot)
SELECT (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001'),
       (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A'),
       (SELECT id_service FROM services WHERE name = 'TEST-Cleaning'),
       '2030-01-07 09:00+00', '2030-01-07 10:00+00', 50;

CREATE FUNCTION pg_temp.add_log(p_previous text, p_new text)
RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO appointment_logs (id_appointment, changed_by, previous_status, new_status)
  SELECT (SELECT a.id_appointment FROM appointments a
          JOIN patients p ON p.id_patient = a.id_patient
          WHERE p.identification = 'TEST-ID-001'),
         (SELECT id_user FROM users WHERE email = 'test.dentist.a@example.test'),
         p_previous, p_new;
$fn$;

SELECT lives_ok(
  $$SELECT pg_temp.add_log(NULL, 'PENDING')$$,
  'a creation log with NULL previous_status is accepted'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_log('BOGUS', 'PENDING')$$,
  '23514',
  'new row for relation "appointment_logs" violates check constraint "appointment_logs_previous_status_check"',
  'an invalid previous_status is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_log('PENDING', 'BOGUS')$$,
  '23514',
  'new row for relation "appointment_logs" violates check constraint "appointment_logs_new_status_check"',
  'an invalid new_status is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_log('PENDING', NULL)$$,
  '23502',
  'null value in column "new_status" of relation "appointment_logs" violates not-null constraint',
  'new_status is required'
);

SELECT * FROM finish();
ROLLBACK;
