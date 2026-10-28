#!/bin/bash
# Instala AutoAudit en una base de datos nueva
# Uso (con tu usuario normal, sin poner sudo adelante):
#     ./instalar.sh nombre_bd
# El script usa sudo por dentro para entrar como el usuario postgres.
BD=${1:-autoaudit_bd}
cd "$(dirname "$0")/sql" || exit 1

# ejecuta psql como el usuario postgres
pg() {
    if [ "$(id -un)" = "postgres" ]; then psql "$@"; else sudo -u postgres psql "$@"; fi
}

if pg -lqt | cut -d'|' -f1 | grep -qw "$BD"; then
    echo "La base $BD ya existe, se usa esa"
else
    pg -c "CREATE DATABASE $BD" || exit 1
fi

# los archivos se leen con "<" para que no importen los permisos de la carpeta
for f in 01_estructura.sql 02_diccionario.sql 03_configuracion.sql \
         04_generador_triggers.sql 05_consultas.sql; do
    echo ">> $f"
    pg -v ON_ERROR_STOP=1 -q -d "$BD" < "$f" || exit 1
done
echo "Listo. Para probar:"
echo "  cat sql/06_datos_prueba.sql sql/07_pruebas.sql | sudo -u postgres psql -d $BD"
