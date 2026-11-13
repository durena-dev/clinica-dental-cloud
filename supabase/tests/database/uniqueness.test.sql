BEGIN;
SELECT plan(16);

INSERT INTO roles (name) VALUES ('DENTIST'), ('PATIENT') ON CONFLICT (name) DO NOTHING;
INSERT INTO users (id_role, full_name, email, password_hash)
SELECT id_role, 'Test Dentist A', 'test.dentist.a@example.test', 'hash' FROM roles WHERE name = 'DENTIST';
INSERT INTO users (id_role, full_name, email, password_hash)
SELECT id_role, 'Test Dentist B', 'test.dentist.b@example.test', 'hash' FROM roles WHERE name = 'DENTIST';
INSERT INTO users (id_role, full_name, email, password_hash)
SELECT id_role, 'Test Patient User', 'test.patient.user@example.test', 'hash' FROM roles WHERE name = 'PATIENT';
INSERT INTO specialties (name) VALUES ('TEST-General');
INSERT INTO dentists (id_user, id_specialty, license_number)
SELECT (SELECT id_user FROM users WHERE email = 'test.dentist.a@example.test'),
       (SELECT id_specialty FROM specialties WHERE name = 'TEST-General'), 'TEST-LIC-A';
INSERT INTO patients (id_user, full_name, identification)
VALUES ((SELECT id_user FROM users WHERE email = 'test.patient.user@example.test'), 'Test Patient One', 'TEST-ID-001');
INSERT INTO dentist_schedules (id_dentist, day_of_week, start_time, end_time)
SELECT id_dentist, 1, '08:00', '12:00' FROM dentists WHERE license_number = 'TEST-LIC-A';

CREATE FUNCTION pg_temp.add_schedule(p_day smallint, p_start time, p_end time)
RETURNS void LANGUAGE sql AS $fn$
  INSERT INTO dentist_schedules (id_dentist, day_of_week, start_time, end_time)
  SELECT id_dentist, p_day, p_start, p_end FROM dentists WHERE license_number = 'TEST-LIC-A';
$fn$;

SELECT throws_ok(
  $$INSERT INTO patients (full_name, identification) VALUES ('Test Patient Two', 'TEST-ID-001')$$,
  '23505',
  'duplicate key value violates unique constraint "patients_identification_key"',
  'duplicate patient identification is rejected'
);

SELECT throws_ok(
  $$INSERT INTO patients (id_user, full_name, identification)
    VALUES ((SELECT id_user FROM users WHERE email = 'test.patient.user@example.test'), 'Test Patient Two', 'TEST-ID-002')$$,
  '23505',
  'duplicate key value violates unique constraint "patients_id_user_key"',
  'a user cannot be linked to two patients'
);

SELECT throws_ok(
  $$INSERT INTO dentists (id_user, id_specialty, license_number)
    SELECT (SELECT id_user FROM users WHERE email = 'test.dentist.b@example.test'),
           (SELECT id_specialty FROM specialties WHERE name = 'TEST-General'), 'TEST-LIC-A'$$,
  '23505',
  'duplicate key value violates unique constraint "dentists_license_number_key"',
  'duplicate dentist license number is rejected'
);

SELECT throws_ok(
  $$INSERT INTO dentists (id_user, id_specialty, license_number)
    SELECT (SELECT id_user FROM users WHERE email = 'test.dentist.a@example.test'),
           (SELECT id_specialty FROM specialties WHERE name = 'TEST-General'), 'TEST-LIC-B'$$,
  '23505',
  'duplicate key value violates unique constraint "dentists_id_user_key"',
  'a user cannot be linked to two dentists'
);

SELECT throws_ok(
  $$INSERT INTO users (id_role, full_name, email, password_hash)
    SELECT id_role, 'Other', 'test.dentist.a@example.test', 'hash' FROM roles WHERE name = 'PATIENT'$$,
  '23505',
  'duplicate key value violates unique constraint "users_email_key"',
  'duplicate user email is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_schedule(1::smallint, '08:00', '10:00')$$,
  '23505',
  'duplicate key value violates unique constraint "dentist_schedules_slot_unique"',
  'a dentist cannot have two schedule slots starting at the same time on the same day'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_schedule(8::smallint, '08:00', '10:00')$$,
  '23514',
  'new row for relation "dentist_schedules" violates check constraint "dentist_schedules_day_of_week_check"',
  'day_of_week above 7 is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_schedule(0::smallint, '08:00', '10:00')$$,
  '23514',
  'new row for relation "dentist_schedules" violates check constraint "dentist_schedules_day_of_week_check"',
  'day_of_week below 1 is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_schedule(2::smallint, '10:00', '10:00')$$,
  '23514',
  'new row for relation "dentist_schedules" violates check constraint "dentist_schedules_time_range_check"',
  'schedule end_time must be greater than start_time'
);

SELECT throws_ok(
  $$INSERT INTO services (name, duration_minutes, price) VALUES ('TEST-Bad duration', 0, 10)$$,
  '23514',
  'new row for relation "services" violates check constraint "services_duration_minutes_check"',
  'service duration_minutes must be positive'
);

SELECT throws_ok(
  $$INSERT INTO services (name, duration_minutes, price) VALUES ('TEST-Bad price', 30, -1)$$,
  '23514',
  'new row for relation "services" violates check constraint "services_price_check"',
  'service price cannot be negative'
);

SELECT lives_ok(
  $$INSERT INTO services (name, duration_minutes, price) VALUES ('TEST-Free checkup', 15, 0)$$,
  'a service with price 0 is allowed'
);

SELECT throws_ok(
  $$INSERT INTO users (id_role, full_name, email, password_hash, status)
    SELECT id_role, 'Other', 'test.bogus.status@example.test', 'hash', 'BOGUS' FROM roles WHERE name = 'PATIENT'$$,
  '23514',
  'new row for relation "users" violates check constraint "users_status_check"',
  'an invalid user status is rejected'
);

SELECT throws_ok(
  $$INSERT INTO patients (full_name, identification, status) VALUES ('Test Patient Three', 'TEST-ID-003', 'BOGUS')$$,
  '23514',
  'new row for relation "patients" violates check constraint "patients_status_check"',
  'an invalid patient status is rejected'
);

SELECT throws_ok(
  $$INSERT INTO dentists (id_user, id_specialty, license_number, status)
    SELECT (SELECT id_user FROM users WHERE email = 'test.dentist.b@example.test'),
           (SELECT id_specialty FROM specialties WHERE name = 'TEST-General'), 'TEST-LIC-C', 'BOGUS'$$,
  '23514',
  'new row for relation "dentists" violates check constraint "dentists_status_check"',
  'an invalid dentist status is rejected'
);

SELECT throws_ok(
  $$INSERT INTO services (name, duration_minutes, price, status) VALUES ('TEST-Bad status', 30, 10, 'BOGUS')$$,
  '23514',
  'new row for relation "services" violates check constraint "services_status_check"',
  'an invalid service status is rejected'
);

SELECT * FROM finish();
ROLLBACK;
