BEGIN;
SELECT plan(7);

INSERT INTO roles (name) VALUES ('DENTIST') ON CONFLICT (name) DO NOTHING;
INSERT INTO users (id_role, full_name, email, password_hash, updated_at)
SELECT id_role, 'Test Dentist A', 'test.dentist.a@example.test', 'hash', '2000-01-01+00' FROM roles WHERE name = 'DENTIST';
INSERT INTO specialties (name) VALUES ('TEST-General');
INSERT INTO dentists (id_user, id_specialty, license_number, updated_at)
SELECT (SELECT id_user FROM users WHERE email = 'test.dentist.a@example.test'),
       (SELECT id_specialty FROM specialties WHERE name = 'TEST-General'), 'TEST-LIC-A', '2000-01-01+00';
INSERT INTO patients (full_name, identification, updated_at)
VALUES ('Test Patient One', 'TEST-ID-001', '2000-01-01+00');
INSERT INTO services (name, duration_minutes, price, updated_at)
VALUES ('TEST-Cleaning', 60, 50, '2000-01-01+00');
INSERT INTO dentist_services (id_dentist, id_service)
SELECT (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A'),
       (SELECT id_service FROM services WHERE name = 'TEST-Cleaning');
INSERT INTO appointments (id_patient, id_dentist, id_service, starts_at, ends_at, price_snapshot, updated_at)
SELECT (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001'),
       (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A'),
       (SELECT id_service FROM services WHERE name = 'TEST-Cleaning'),
       '2030-01-07 09:00+00', '2030-01-07 10:00+00', 50, '2000-01-01+00';
INSERT INTO medical_records (id_appointment, physical_exam, diagnosis, treatment_plan, updated_at)
SELECT id_appointment, 'exam', 'dx', 'plan', '2000-01-01+00' FROM appointments
WHERE id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001');

UPDATE users SET phone = '555-0001' WHERE email = 'test.dentist.a@example.test';
UPDATE patients SET phone = '555-0002' WHERE identification = 'TEST-ID-001';
UPDATE dentists SET status = 'INACTIVE' WHERE license_number = 'TEST-LIC-A';
UPDATE services SET description = 'updated' WHERE name = 'TEST-Cleaning';
UPDATE appointments SET status = 'CONFIRMED'
WHERE id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001');
UPDATE medical_records SET symptoms = 'updated'
WHERE id_appointment = (SELECT id_appointment FROM appointments
                        WHERE id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001'));

SELECT is((SELECT updated_at FROM users WHERE email = 'test.dentist.a@example.test'), now(),
  'users.updated_at is refreshed on update');
SELECT is((SELECT updated_at FROM patients WHERE identification = 'TEST-ID-001'), now(),
  'patients.updated_at is refreshed on update');
SELECT is((SELECT updated_at FROM dentists WHERE license_number = 'TEST-LIC-A'), now(),
  'dentists.updated_at is refreshed on update');
SELECT is((SELECT updated_at FROM services WHERE name = 'TEST-Cleaning'), now(),
  'services.updated_at is refreshed on update');
SELECT is((SELECT updated_at FROM appointments
           WHERE id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001')), now(),
  'appointments.updated_at is refreshed on update');
SELECT is((SELECT updated_at FROM medical_records
           WHERE id_appointment = (SELECT id_appointment FROM appointments
                                   WHERE id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001'))), now(),
  'medical_records.updated_at is refreshed on update');

UPDATE users SET updated_at = '2000-01-01+00' WHERE email = 'test.dentist.a@example.test';

SELECT is((SELECT updated_at FROM users WHERE email = 'test.dentist.a@example.test'), now(),
  'an explicit updated_at value is overwritten by the trigger');

SELECT * FROM finish();
ROLLBACK;
