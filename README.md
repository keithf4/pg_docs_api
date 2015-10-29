# A Simple Document API For PostgreSQL

This project is a fork of Rob Conery's pg_doc_api (https://github.com/robconery/pg_docs_api). He originally wrote it in PLV8, but mentioned in his docs that a plpgsql conversion would be appreciated, so I gave it a shot. The aim seems to be to make an interface more like mongodb and other document stores where things "just work" when you throw schemaless data at it. The advantage of postgres is of course you gain ACID compliance and all the advantages of a relational model along with that schemaless flexibility.

## Requirements

The only requirement so far is PostgreSQL 9.4 due to using the new JSONB data type.

The original PLV8 functions are still available if desired and you must have PLV8 installed already.

## Installation

This code is managed as an extension. So you just have to run

    make
    make install

And then while logged into the database run

    CREATE EXTENSION pg_docs_api;


If you'd like to try the original PLV8 functions, you can pass a flag to the make command

    make PLV8=1

## Usage

The following is just for the plgpsql functions. If you'd like info on the original PLV8 functions, please see the repo linked above.

*`create_document(p_tablename text, OUT tablename text, OUT schemaname text) RETURNS record`*

 * Creates a table used to store your documents. Contains no data.
 * Your tablename must be schema qualified
 * The table has the structure below.
    + *id* - unique id value given to each document. This value is also always added to the document itself.
    + *body* -  the document itself stored as jsonb
    + *search* - a tsvector column based on the values in the document used for full-text search (FTS)
    + *created_at* - a timestamp of when the document was created
    + *updated_at* - a timestamp that is updated whenever the document is updated using the function interfaces
 * Returns the schema & tablename of the document table it created
 
```
                                    Table "keith.testing"
   Column   |           Type           |                      Modifiers                       
------------+--------------------------+------------------------------------------------------
 id         | integer                  | not null default nextval('testing_id_seq'::regclass)
 body       | jsonb                    | not null
 search     | tsvector                 | 
 created_at | timestamp with time zone | not null default now()
 updated_at | timestamp with time zone | not null default now()
Indexes:
    "testing_pkey" PRIMARY KEY, btree (id)
    "testing_body_idx" gin (body jsonb_path_ops)
    "testing_search_idx" gin (search)
Triggers:
    testing_trig BEFORE INSERT OR UPDATE OF body ON testing FOR EACH ROW EXECUTE PROCEDURE update_search()
```

*`save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb`*

 * Save a jsonb document to the given table.
 * If the table does not exist already, it will be created
 * If an "id" key is given in the document, it will be set as the primary key value
 * If the given "id" primary key already exists, it will update that row with the given document
 * If the given "id" does not exist, that row will be added
 * If an "id" is not given, then the next value in the sequence will be used and automatically added to the document.
 * The "search" column will automatically be updated with the latest relevant FTS values based on the given document.
 * The "updated_at" column will automatically be updated to the timestamp at the time save is run.
 * The function will return a copy of the jsonb document that is given if successfully stored.
 * WARNING: Until 9.5 is released, the UPSERT used in this function is not 100% transaction safe and may result in deadlocks on a high traffic system. Use with caution.


*`find_document(p_tablename text, p_criteria jsonb, p_orderbykey text DEFAULT 'id', p_orderby text DEFAULT 'ASC') RETURNS SETOF jsonb`*

 * Searches the given table for documents that contain the given jsonb string and returns the full document(s).
 * It's pretty much the equivalent of the @> operator when used with two jsonb values.
 * p_orderbykey allows you to tell it to sort the returned documents by the given key name.
 * p_orderby allows you to tell it which order to return that sort in. Valid values are "ASC" (the default)  and "DESC".


*`search_document(p_tablename text, p_query text) RETURNS SETOF jsonb`*

 * Performs a full-text search on the given document table for documents containing the given string in their values.
 * Returns the full jsonb document(s) ranked by relevance.

