# Postgres image for the legacy stack, with the bootstrap baked in.
# Baking the init script into the image (instead of a bind mount) keeps file
# permissions sane across hosts and matches a production-equivalent build.
FROM postgres:16-alpine
COPY init/01-roles-and-schemas.sh /docker-entrypoint-initdb.d/01-roles-and-schemas.sh
