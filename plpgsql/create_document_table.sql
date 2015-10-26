/* 
    Issues:
     - Use text type, not varchar
     - Assumes table name will be docs
     - No need to name indexes. Postgres will name with column appropriately

create function create_document_table(name varchar, out boolean)
as $$
  var sql = "create table " + name + "(" +
    "id serial primary key," +
    "body jsonb not null," +
    "search tsvector," +
    "created_at timestamptz default now() not null," +
    "updated_at timestamptz default now() not null);";

  plv8.execute(sql);
  plv8.execute("create index idx_" + name + " on docs using GIN(body jsonb_path_ops)");
  plv8.execute("create index idx_" + name + "_search on docs using GIN(search)");
  return true;
$$ language plv8;
*/

CREATE OR REPLACE FUNCTION create_document_table(p_tablename text, OUT tablename text, OUT schemaname text) RETURNS record
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

EXECUTE format ('CREATE INDEX ON %I.%I USING GIN(body jsonb_path_ops)', schemaname, tablename);
EXECUTE format ('CREATE INDEX ON %I.%I USING GIN(search)', schemaname, tablename);

END
$$;
