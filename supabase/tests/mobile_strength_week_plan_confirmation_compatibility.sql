\set ON_ERROR_STOP on
-- Both isolation modes must preserve plan confirmation for owners without signup Y.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='3s';
SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
\ir fixtures/mobile_strength_week_plan_confirmation_compatibility.sql
ROLLBACK;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='3s';
SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
\ir fixtures/mobile_strength_week_plan_confirmation_compatibility.sql
ROLLBACK;
