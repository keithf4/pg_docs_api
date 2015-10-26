/*
-- id key does not exist, so insert new value and create id key in given document
*/
CREATE OR REPLACE FUNCTION insert_document(p_tablename text, p_doc_string jsonb, p_id bigint DEFAULT NULL) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE

v_doc           jsonb;
v_returning     record;
v_schemaname    text;
v_tablename     text;

BEGIN

SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM pg_catalog.pg_tables WHERE schemaname||'.'||tablename = p_tablename;

EXECUTE format('INSERT INTO %I.%I (body) VALUES (%L) RETURNING *', v_schemaname, v_tablename, p_doc_string)
    INTO v_returning;

RAISE NOTICE 'insert_document: v_returning.id: %', v_returning.id;

WITH json_union AS (
    SELECT * FROM jsonb_each_text(p_doc_string)
    UNION 
    SELECT * FROM jsonb_each_text(json_build_object('id', v_returning.id)::jsonb)
)
SELECT json_object_agg(key,value) 
INTO v_doc
FROM json_union;

EXECUTE format('UPDATE %I.%I SET body = %L WHERE id = %L'
    , v_schemaname
    , v_tablename
    , v_doc
    , v_returning.id);

RETURN v_doc;

END
$$;
