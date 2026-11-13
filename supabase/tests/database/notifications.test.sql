BEGIN;
SELECT plan(7);

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

CREATE FUNCTION pg_temp.add_notification(p_type text, p_channel text, p_status text, p_retry smallint DEFAULT 0)
RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO notifications (id_appointment, type, channel, recipient, status, retry_count, scheduled_for)
  SELECT a.id_appointment, p_type, p_channel, 'test.patient@example.test', p_status, p_retry, '2030-01-06 09:00+00'
  FROM appointments a
  WHERE a.id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001');
$fn$;

SELECT lives_ok(
  $$SELECT pg_temp.add_notification('CONFIRMATION', 'EMAIL', 'CANCELLED')$$,
  'CANCELLED is an accepted notification status'
);

SELECT lives_ok(
  $$SELECT pg_temp.add_notification('REMINDER', 'EMAIL', 'FAILED')$$,
  'FAILED is an accepted notification status'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_notification('REMINDER', 'EMAIL', 'BOGUS')$$,
  '23514',
  'new row for relation "notifications" violates check constraint "notifications_status_check"',
  'an invalid notification status is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_notification('BOGUS', 'EMAIL', 'PENDING')$$,
  '23514',
  'new row for relation "notifications" violates check constraint "notifications_type_check"',
  'an invalid notification type is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_notification('REMINDER', 'SMS', 'PENDING')$$,
  '23514',
  'new row for relation "notifications" violates check constraint "notifications_channel_check"',
  'an invalid notification channel is rejected'
);

SELECT lives_ok(
  $$SELECT pg_temp.add_notification('REMINDER', 'EMAIL', 'PENDING', 0::smallint)$$,
  'retry_count = 0 is accepted'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_notification('REMINDER', 'EMAIL', 'PENDING', (-1)::smallint)$$,
  '23514',
  'new row for relation "notifications" violates check constraint "notifications_retry_count_check"',
  'a negative retry_count is rejected'
);

SELECT * FROM finish();
ROLLBACK;
