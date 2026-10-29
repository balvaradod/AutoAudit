#!/bin/bash
# Prepara y abre la interfaz web de AutoAudit con un solo comando.
# Uso (con tu usuario normal, sin poner sudo adelante):
#     ./iniciar_interfaz.sh una_clave
# "una_clave" es la contrasena que se le pone al usuario postgres de la base
# de datos (es la que se escribe despues en la pagina de inicio de sesion).
# Si ya le pusiste contrasena antes, se puede ejecutar sin ella:
#     ./iniciar_interfaz.sh
#
# Antes hay que haber instalado la base de datos con:  ./instalar.sh autoaudit_bd

CLAVE=$1
CARPETA="$(cd "$(dirname "$0")" && pwd)"
ENTORNO="$HOME/entorno_autoaudit"

# ejecuta psql como el usuario postgres
pg() {
    if [ "$(id -un)" = "postgres" ]; then psql "$@"; else sudo -u postgres psql "$@"; fi
}

# 1. revisar que la base de datos exista
if ! pg -lqt | cut -d'|' -f1 | grep -qw autoaudit_bd; then
    echo "No existe la base autoaudit_bd. Primero ejecuta: ./instalar.sh autoaudit_bd"
    exit 1
fi

# 2. ponerle contrasena al usuario postgres (si se escribio una)
if [ -n "$CLAVE" ]; then
    case "$CLAVE" in
        *\'*) echo "La contrasena no puede llevar comillas simples (')"; exit 1 ;;
    esac
    pg -c "ALTER USER postgres PASSWORD '$CLAVE';" || exit 1
else
    echo "(No se cambio la contrasena de postgres. Si no tienes una, ejecuta: ./iniciar_interfaz.sh una_clave)"
fi

# 3. revisar Python
if ! command -v python3 >/dev/null 2>&1; then
    echo "Falta Python. Instalalo con: sudo apt install -y python3 python3-venv"
    exit 1
fi

# 4. crear el entorno de Python (solo la primera vez)
if [ ! -f "$ENTORNO/bin/activate" ]; then
    echo ">> Creando el entorno de Python..."
    if ! python3 -m venv "$ENTORNO"; then
        echo "No se pudo crear el entorno. Instala: sudo apt install -y python3-venv"
        rm -rf "$ENTORNO"
        exit 1
    fi
fi
source "$ENTORNO/bin/activate"

# 5. instalar lo que necesita la interfaz
echo ">> Instalando Flask y psycopg2..."
pip install -q -r "$CARPETA/interfaz/requirements.txt" || exit 1

# 6. correr la interfaz
echo ""
echo "================================================================"
echo " Interfaz lista. Abre en el navegador:  http://localhost:5000"
echo " Servidor: localhost   Puerto: 5432   Base: autoaudit_bd"
echo " Usuario: postgres     Contrasena: la que pusiste arriba"
echo " Para detenerla presiona Ctrl + C"
echo "================================================================"
cd "$CARPETA/interfaz" && python3 app.py
