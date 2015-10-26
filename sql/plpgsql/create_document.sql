CREATE FUNCTION create_document(p_tablename text, OUT tablename text, OUT schemaname text) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

IF position('.' in p_tablename) > 0 THEN
    schemaname := split_part(p_tablename, '.', 1); 
    tablename := split_part(p_tablename, '.', 2);
ELSE
    RAISE EXCEPTION 'tablename must be schema qualified';
END IF;

EXECUTE format('CREATE TABLE %I.%I (
                    id serial PRIMARY KEY
                    , body jsonb NOT NULL
                    , search tsvector
                    , created_at timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL
                    , updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL
                    )'
                , schemaname
                , tablename
            );

EXECUTE format('CREATE INDEX ON %I.%I USING GIN(body jsonb_path_ops)', schemaname, tablename);
EXECUTE format('CREATE INDEX ON %I.%I USING GIN(search)', schemaname, tablename);

EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF body
                ON %I.%I
                FOR EACH ROW
                EXECUTE PROCEDURE @extschema@.update_search()'
            , tablename||'_trig'
            , schemaname
            , tablename
        );
END
$$;
