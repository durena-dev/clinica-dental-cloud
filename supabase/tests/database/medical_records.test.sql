BEGIN;
SELECT plan(6);

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

CREATE FUNCTION pg_temp.add_record(p_exam text, p_diagnosis text, p_plan text,
                                   p_symptoms text DEFAULT NULL, p_rx text DEFAULT NULL, p_notes text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO medical_records (id_appointment, physical_exam, diagnosis, treatment_plan, symptoms, prescriptions, clinical_notes)
  SELECT a.id_appointment, p_exam, p_diagnosis, p_plan, p_symptoms, p_rx, p_notes
  FROM appointments a
  WHERE a.id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001');
$fn$;

SELECT lives_ok(
  $$SELECT pg_temp.add_record('exam', 'dx', 'plan')$$,
  'symptoms, prescriptions and clinical_notes are optional'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_record(NULL, 'dx', 'plan')$$,
  '23502',
  'null value in column "physical_exam" of relation "medical_records" violates not-null constraint',
  'physical_exam is required'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_record('exam', NULL, 'plan')$$,
  '23502',
  'null value in column "diagnosis" of relation "medical_records" violates not-null constraint',
  'diagnosis is required'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_record('exam', 'dx', NULL)$$,
  '23502',
  'null value in column "treatment_plan" of relation "medical_records" violates not-null constraint',
  'treatment_plan is required'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_record('exam 2', 'dx 2', 'plan 2', 'sym', 'rx', 'notes')$$,
  '23505',
  'duplicate key value violates unique constraint "medical_records_id_appointment_key"',
  'only one medical record per appointment is allowed'
);

SELECT throws_ok(
  $$DELETE FROM appointments
    WHERE id_patient = (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001')$$,
  '23503',
  'update or delete on table "appointments" violates foreign key constraint "medical_records_id_appointment_fkey" on table "medical_records"',
  'an appointment with a medical record cannot be deleted'
);

SELECT * FROM finish();
ROLLBACK;
