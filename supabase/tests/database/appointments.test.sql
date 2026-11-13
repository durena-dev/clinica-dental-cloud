BEGIN;
SELECT plan(15);

INSERT INTO roles (name) VALUES ('DENTIST') ON CONFLICT (name) DO NOTHING;
INSERT INTO users (id_role, full_name, email, password_hash)
SELECT id_role, 'Test Dentist A', 'test.dentist.a@example.test', 'hash' FROM roles WHERE name = 'DENTIST';
INSERT INTO users (id_role, full_name, email, password_hash)
SELECT id_role, 'Test Dentist B', 'test.dentist.b@example.test', 'hash' FROM roles WHERE name = 'DENTIST';
INSERT INTO specialties (name) VALUES ('TEST-General');
INSERT INTO dentists (id_user, id_specialty, license_number)
SELECT u.id_user, (SELECT id_specialty FROM specialties WHERE name = 'TEST-General'),
       CASE u.email WHEN 'test.dentist.a@example.test' THEN 'TEST-LIC-A' ELSE 'TEST-LIC-B' END
FROM users u WHERE u.email IN ('test.dentist.a@example.test', 'test.dentist.b@example.test');
INSERT INTO patients (full_name, identification) VALUES ('Test Patient One', 'TEST-ID-001');
INSERT INTO services (name, duration_minutes, price) VALUES ('TEST-Cleaning', 60, 50), ('TEST-Extraction', 30, 80);
-- Extraction is intentionally not enabled for any dentist
INSERT INTO dentist_services (id_dentist, id_service)
SELECT d.id_dentist, s.id_service
FROM dentists d, services s
WHERE d.license_number IN ('TEST-LIC-A', 'TEST-LIC-B') AND s.name = 'TEST-Cleaning';

CREATE FUNCTION pg_temp.add_appt(p_license text, p_service text, p_start timestamptz, p_end timestamptz,
                                 p_status text DEFAULT 'PENDING', p_price numeric DEFAULT 50)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO appointments (id_patient, id_dentist, id_service, starts_at, ends_at, status, price_snapshot)
  SELECT (SELECT id_patient FROM patients WHERE identification = 'TEST-ID-001'),
         (SELECT id_dentist FROM dentists WHERE license_number = p_license),
         (SELECT id_service FROM services WHERE name = p_service),
         p_start, p_end, p_status, p_price;
$$;

SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-07 09:00+00', '2030-01-07 10:00+00');

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-07 09:30+00', '2030-01-07 10:30+00')$$,
  '23P01',
  'conflicting key value violates exclusion constraint "appointments_no_overlap"',
  'overlapping appointments for the same dentist are rejected'
);

SELECT lives_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-07 09:30+00', '2030-01-07 10:30+00', 'CANCELLED')$$,
  'a cancelled appointment does not block the slot'
);

SELECT lives_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-07 10:00+00', '2030-01-07 11:00+00')$$,
  'back-to-back appointments for the same dentist are allowed'
);

SELECT lives_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-B', 'TEST-Cleaning', '2030-01-07 09:00+00', '2030-01-07 10:00+00')$$,
  'same time slot with a different dentist is allowed'
);

SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-13 09:00+00', '2030-01-13 10:00+00', 'NO_SHOW');
SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-14 09:00+00', '2030-01-14 10:00+00', 'COMPLETED');
SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-15 09:00+00', '2030-01-15 10:00+00', 'IN_PROGRESS');

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-13 09:30+00', '2030-01-13 10:30+00')$$,
  '23P01',
  'conflicting key value violates exclusion constraint "appointments_no_overlap"',
  'a NO_SHOW appointment still blocks the slot'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-14 09:30+00', '2030-01-14 10:30+00')$$,
  '23P01',
  'conflicting key value violates exclusion constraint "appointments_no_overlap"',
  'a COMPLETED appointment still blocks the slot'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-15 09:30+00', '2030-01-15 10:30+00')$$,
  '23P01',
  'conflicting key value violates exclusion constraint "appointments_no_overlap"',
  'an IN_PROGRESS appointment still blocks the slot'
);

SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-16 09:00+00', '2030-01-16 10:00+00');

SELECT lives_ok(
  $$UPDATE appointments SET status = 'CANCELLED'
    WHERE id_dentist = (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A')
      AND starts_at = '2030-01-16 09:00+00'$$,
  'a pending appointment can be cancelled'
);

SELECT lives_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-16 09:00+00', '2030-01-16 10:00+00')$$,
  'the slot of a cancelled appointment can be booked again'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Extraction', '2030-01-08 09:00+00', '2030-01-08 09:30+00')$$,
  '23503',
  'insert or update on table "appointments" violates foreign key constraint "appointments_dentist_service_fkey"',
  'a service not enabled for the dentist is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-09 10:00+00', '2030-01-09 10:00+00')$$,
  '23514',
  'new row for relation "appointments" violates check constraint "appointments_time_range_check"',
  'ends_at equal to starts_at is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-09 11:00+00', '2030-01-09 10:00+00')$$,
  '23514',
  'new row for relation "appointments" violates check constraint "appointments_time_range_check"',
  'ends_at before starts_at is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-10 09:00+00', '2030-01-10 10:00+00', 'BOGUS')$$,
  '23514',
  'new row for relation "appointments" violates check constraint "appointments_status_check"',
  'an invalid appointment status is rejected'
);

SELECT throws_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-A', 'TEST-Cleaning', '2030-01-12 09:00+00', '2030-01-12 10:00+00', 'PENDING', -1)$$,
  '23514',
  'new row for relation "appointments" violates check constraint "appointments_price_snapshot_check"',
  'a negative price_snapshot is rejected'
);

SELECT lives_ok(
  $$SELECT pg_temp.add_appt('TEST-LIC-B', 'TEST-Cleaning',
                            '2030-02-01 09:00+00'::timestamptz + make_interval(days => s.n),
                            '2030-02-01 10:00+00'::timestamptz + make_interval(days => s.n), s.st)
    FROM (VALUES (1, 'PENDING'), (2, 'CONFIRMED'), (3, 'IN_PROGRESS'),
                 (4, 'COMPLETED'), (5, 'CANCELLED'), (6, 'NO_SHOW')) AS s(n, st)$$,
  'all six valid appointment statuses are accepted'
);

SELECT * FROM finish();
ROLLBACK;
