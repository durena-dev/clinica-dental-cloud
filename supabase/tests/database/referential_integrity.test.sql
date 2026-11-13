BEGIN;
SELECT plan(5);

INSERT INTO roles (name) VALUES ('DENTIST'), ('ADMIN') ON CONFLICT (name) DO NOTHING;
INSERT INTO users (id_role, full_name, email, password_hash)
SELECT id_role, 'Test Admin', 'test.admin@example.test', 'hash' FROM roles WHERE name = 'ADMIN';
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

CREATE TEMP TABLE test_ids AS
SELECT (SELECT id_appointment FROM appointments
        WHERE id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001')) AS appointment,
       (SELECT id_user FROM users WHERE email = 'test.admin@example.test') AS log_user;

INSERT INTO appointment_logs (id_appointment, changed_by, previous_status, new_status)
SELECT appointment, log_user, NULL, 'PENDING' FROM test_ids;

-- Notifications live on a second appointment so the log check above stays isolated
INSERT INTO appointments (id_patient, id_dentist, id_service, starts_at, ends_at, price_snapshot)
SELECT (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001'),
       (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A'),
       (SELECT id_service FROM services WHERE name = 'TEST-Cleaning'),
       '2030-01-08 09:00+00', '2030-01-08 10:00+00', 50;

INSERT INTO notifications (id_appointment, type, recipient, scheduled_for)
SELECT a.id_appointment, 'CONFIRMATION', 'test.patient@example.test', '2030-01-07 09:00+00'
FROM appointments a
WHERE a.starts_at = '2030-01-08 09:00+00'
  AND a.id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001');

SELECT throws_ok(
  $$DELETE FROM patients WHERE identification = 'TEST-ID-001'$$,
  '23503',
  'update or delete on table "patients" violates foreign key constraint "appointments_id_patient_fkey" on table "appointments"',
  'a patient with appointments cannot be deleted'
);

SELECT throws_ok(
  $$DELETE FROM appointments WHERE id_appointment = (SELECT appointment FROM test_ids)$$,
  '23503',
  'update or delete on table "appointments" violates foreign key constraint "appointment_logs_id_appointment_fkey" on table "appointment_logs"',
  'an appointment with logs cannot be deleted'
);

SELECT throws_ok(
  $$DELETE FROM appointments
    WHERE starts_at = '2030-01-08 09:00+00'
      AND id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001')$$,
  '23503',
  'update or delete on table "appointments" violates foreign key constraint "notifications_id_appointment_fkey" on table "notifications"',
  'an appointment with notifications cannot be deleted'
);

SELECT throws_ok(
  $$DELETE FROM users WHERE id_user = (SELECT log_user FROM test_ids)$$,
  '23503',
  'update or delete on table "users" violates foreign key constraint "appointment_logs_changed_by_fkey" on table "appointment_logs"',
  'a user referenced by appointment logs cannot be deleted'
);

SELECT throws_ok(
  $$DELETE FROM dentist_services
    WHERE id_dentist = (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A')$$,
  '23503',
  'update or delete on table "dentist_services" violates foreign key constraint "appointments_dentist_service_fkey" on table "appointments"',
  'a dentist-service pair used by appointments cannot be removed'
);

SELECT * FROM finish();
ROLLBACK;
