BEGIN;
  -- Create pgvector extension
  create extension vector
  with
    schema extensions;
COMMIT;
