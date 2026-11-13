BEGIN;
SELECT plan(3);

SELECT is(
  (SELECT count(*) FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')),
  13::bigint,
  'public schema has the 13 expected tables'
);

SELECT is(
  (SELECT array_agg(c.relname::text ORDER BY c.relname) FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity),
  NULL::text[],
  'row level security is enabled on every public table'
);

SELECT is(
  (SELECT count(*) FROM pg_policies WHERE schemaname = 'public'),
  0::bigint,
  'no row level security policies are defined in public'
);

SELECT * FROM finish();
ROLLBACK;
