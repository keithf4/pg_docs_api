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
