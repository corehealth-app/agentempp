-- PostgreSQL applies the built-in PUBLIC EXECUTE grant globally. A schema-only
-- revoke cannot override it, so this must be a role-global default.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;
