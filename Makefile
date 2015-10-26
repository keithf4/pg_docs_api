EXTENSION = pg_docs_api
EXTVERSION = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

PG_CONFIG = pg_config
PG94 = $(shell $(PG_CONFIG) --version | egrep " 8\.| 9\.0| 9\.1| 9\.2| 9\.3" > /dev/null && echo no || echo yes)

ifeq ($(PG94),yes)
#DOCS = $(wildcard doc/*.md)
# If user does not want the background worker, run: make NO_BGW=1
all: sql/$(EXTENSION)--$(EXTVERSION).sql

ifneq ($(PLV8),)
# Use plv8 files
sql/$(EXTENSION)--$(EXTVERSION).sql: sql/plv8sql/*.sql
	cat $^ > $@
DATA = $(wildcard plv8sql/updates/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
else
# Use plpgsql files
sql/$(EXTENSION)--$(EXTVERSION).sql: sql/plpgsql/*.sql
	cat $^ > $@
DATA = $(wildcard plpgsql/updates/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
endif

EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql
else
$(error Minimum version of PostgreSQL required is 9.4.0)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
