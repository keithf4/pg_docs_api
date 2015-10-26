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
/*
create function filter_documents(tbl varchar, criteria varchar)
returns setof jsonb
as $$
  var valid = JSON.parse(criteria);//this will throw if it invalid
  var results = plv8.execute("select body from " + tbl + " where body @> $1;",criteria);
  var out = [];
  for(var i = 0;i < results.length; i++){
    out.push(results[i].body);
  }
  return out;
$$ language plv8;
*/
/*
create function find_document(tbl varchar, id int, out jsonb)
as $$
  //find by the id of the row
  var result = plv8.execute("select * from " + tbl + " where id=$1;",id);
  return result[0] ? result[0].body : null;

$$ language plv8;

create function find_document(tbl varchar, criteria varchar, orderby varchar default 'id')
returns jsonb
as $$
  var valid = JSON.parse(criteria);//this will throw if it invalid
  var results = plv8.execute("select body from " + tbl + " where body @> $1 order by body ->> '" + orderby + "' limit 1;",criteria);
  return results[0] ? results[0].body : null
$$ language plv8;
*/
/*
create extension plv8;
*/
/*create function save_document(tbl varchar, doc_string jsonb)
returns jsonb
as $$
  var doc = JSON.parse(doc_string);

  var exists = plv8.execute("select table_name from information_schema.tables where table_name = $1", tbl)[0];
  if(!exists){
    plv8.execute("select create_document_table('" + tbl + "');");
  }

  var executeSql = function(theDoc){
    var result = null;
    var id = theDoc.id;
    var toSave = JSON.stringify(theDoc);

    if(id){
      result=plv8.execute("update " + tbl + " set body=$1, updated_at = now() where id=$2 returning *;",toSave, id);
    }else{
      result=plv8.execute("insert into " + tbl + "(body) values($1) returning *;", toSave);

      id = result[0].id;
      //put the id back on the document
      theDoc.id = id;
      //resave it
      result = plv8.execute("update " + tbl + " set body=$1 where id=$2 returning *;",JSON.stringify(theDoc),id);
    }
    plv8.execute("select update_search($1,$2)", tbl, id);
    return result ? result[0].body : null;
  }
  var out = null;
  if(doc instanceof Array){
    var bulkResult = [];
    for(var i = 0; i < doc.length;i++){
      executeSql(doc[i]);
    }
    out = JSON.stringify({success : true, count : i});
  }else{
    out = executeSql(doc);
  }
  return out;
$$ language plv8;
*/
/*
http://michael.otacoo.com/postgresql-2/manipulating-jsonb-data-with-key-unique/

Issues with above
    -- Does not insert document if id value does not exist
        -- Requires upsert introduced in 9.5 to actually be transaction safe
*/

CREATE OR REPLACE FUNCTION save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE

v_doc           jsonb;
v_id            text;
v_returning     record;
v_schemaname    text;
v_tablename     text;

BEGIN

IF position('.' in p_tablename) < 1 THEN
    RAISE EXCEPTION 'tablename must be schema qualified';
END IF;

/* Working on array handling
IF jsonb_typeof(p_doc_string) = 'array' THEN
    FOR v_element IN jsonb_array_elements(p_doc_string) LOOP
        PERFORM save_document(v_element);
    END LOOP;
END IF;
*/

SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM pg_catalog.pg_tables WHERE schemaname||'.'||tablename = p_tablename;

IF v_tablename IS NULL THEN
    SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM create_document_table(p_tablename);
END IF;

v_doc := p_doc_string;

IF p_doc_string ? 'id' THEN

    SELECT v_doc ->> 'id' INTO v_id;
    LOOP
        -- Implemenent true UPSERT in 9.5. Following solution still has race conditions
        EXECUTE format('UPDATE %I.%I SET body = %L WHERE id = %L RETURNING *'
            , v_schemaname
            , v_tablename
            , v_doc
            , v_id::bigint) INTO v_returning;
        RAISE NOTICE 'save_document: v_returning.id:% ', v_returning.id;
        IF v_returning.id IS NOT NULL THEN
            RETURN v_doc;
        END IF;
        BEGIN
            EXECUTE format('INSERT INTO %I.%I (id, body) VALUES (%L, %L) RETURNING *', v_schemaname, v_tablename, v_id, p_doc_string);
            RETURN v_doc;
        EXCEPTION WHEN unique_violation THEN
            -- Do nothing and loop to try the UPDATE again.
        END;
    END LOOP;

ELSE -- id if

    EXECUTE format('INSERT INTO %I.%I (body) VALUES (%L) RETURNING *', v_schemaname, v_tablename, p_doc_string)
        INTO v_returning;

    RAISE NOTICE 'insert_document: v_returning.id: %', v_returning.id;

    -- There is no native way to add fields to a json column. Pulled this method from
    -- http://michael.otacoo.com/postgresql-2/manipulating-jsonb-data-with-key-unique/
    WITH json_union AS (
        SELECT * FROM jsonb_each(p_doc_string)
        UNION 
        SELECT * FROM jsonb_each(json_build_object('id', v_returning.id)::jsonb)
    )
    SELECT json_object_agg(key,value) 
    INTO v_doc
    FROM json_union;

    EXECUTE format('UPDATE %I.%I SET body = %L WHERE id = %L'
        , v_schemaname
        , v_tablename
        , v_doc
        , v_returning.id);

    -- id key does not exist, so insert new value and create id key in given document
    --TODO REMOVE SELECT insert_document(p_tablename, v_doc) INTO v_doc;

        /* Get the non-array split working first
    IF json_typeof(p_doc_string) = 'array' THEN
    END IF;
    */
END IF; -- id if

RETURN v_doc;

END
$$;
/*
create function search_documents(tbl varchar, query varchar)
returns setof jsonb
as $$
  var sql = "select body, ts_rank_cd(search,to_tsquery($1)) as rank from " + tbl +
    " where search @@ to_tsquery($1) " +
    " order by rank desc;"
  var results = plv8.execute(sql,query);
  var out = [];
  for(var i = 0; i < results.length; i++){
    out.push(results[i].body);
  }
  return out;
$$ language plv8;
*/
/*
create function update_search(tbl varchar, id int)
returns boolean
as $$
  //get the record
  var found = plv8.execute("select body from " + tbl + " where id=$1",id)[0];
  if(found){
    var doc = JSON.parse(found.body);
    var searchFields = ["name","email","first","first_name","last","last_name","description","title","city","state","address","street"];
    var searchVals = [];
    for(var key in doc){
      if(searchFields.indexOf(key) > -1){
        searchVals.push(doc[key]);
      }
    };

    if(searchVals.length > 0){
      var updateSql = "update " + tbl + " set search = to_tsvector($1) where id =$2";
      plv8.execute(updateSql, searchVals.join(" "), id);
    }
    return true;
  }else{
    return false;
  }

$$ language plv8;

CREATE FUNCTION update_search(p_tablename text, id bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE

BEGIN

    -- See if there's a json function to return all field names from a jsonb column
    -- make this a trigger on the created table instead of a standalone funtion
END
$$;
*/
