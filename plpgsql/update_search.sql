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
END
$$;
