BEGIN;
SELECT plan(9);

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

CREATE TEMP TABLE test_ids AS
SELECT (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-A') AS dentist_a,
       (SELECT id_dentist FROM dentists WHERE license_number = 'TEST-LIC-B') AS dentist_b;

INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at, reason)
SELECT dentist_a, '2030-02-01 09:00+00', '2030-02-01 10:00+00', 'Meeting' FROM test_ids;

SELECT throws_ok(
  $$INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at)
    SELECT dentist_a, '2030-02-01 09:30+00', '2030-02-01 10:30+00' FROM test_ids$$,
  '23P01',
  'conflicting key value violates exclusion constraint "dentist_blocks_no_overlap"',
  'overlapping blocks for the same dentist are rejected'
);

SELECT lives_ok(
  $$INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at)
    SELECT dentist_a, '2030-02-01 10:00+00', '2030-02-01 11:00+00' FROM test_ids$$,
  'back-to-back blocks are allowed'
);

SELECT lives_ok(
  $$INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at)
    SELECT dentist_b, '2030-02-01 09:00+00', '2030-02-01 10:00+00' FROM test_ids$$,
  'the same block time slot for a different dentist is allowed'
);

SELECT throws_ok(
  $$INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at)
    SELECT dentist_a, '2030-02-02 10:00+00', '2030-02-02 10:00+00' FROM test_ids$$,
  '23514',
  'new row for relation "dentist_blocks" violates check constraint "dentist_blocks_time_range_check"',
  'block ends_at equal to starts_at is rejected'
);

SELECT throws_ok(
  $$INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at)
    SELECT dentist_a, '2030-02-02 11:00+00', '2030-02-02 10:00+00' FROM test_ids$$,
  '23514',
  'new row for relation "dentist_blocks" violates check constraint "dentist_blocks_time_range_check"',
  'block ends_at before starts_at is rejected'
);

INSERT INTO dentist_schedules (id_dentist, day_of_week, start_time, end_time)
SELECT dentist_a, 1, '08:00', '12:00' FROM test_ids;

SELECT lives_ok(
  $$DELETE FROM dentists WHERE id_dentist = (SELECT dentist_a FROM test_ids)$$,
  'deleting a dentist without appointments cascades to schedules and blocks'
);

SELECT is(
  (SELECT count(*) FROM dentist_blocks WHERE id_dentist = (SELECT dentist_a FROM test_ids)), 0::bigint,
  'dentist blocks are removed together with the dentist'
);

SELECT is(
  (SELECT count(*) FROM dentist_schedules WHERE id_dentist = (SELECT dentist_a FROM test_ids)), 0::bigint,
  'dentist schedules are removed together with the dentist'
);

SELECT is(
  (SELECT count(*) FROM dentist_blocks WHERE id_dentist = (SELECT dentist_b FROM test_ids)), 1::bigint,
  'blocks of other dentists are not affected by the cascade'
);

SELECT * FROM finish();
ROLLBACK;
