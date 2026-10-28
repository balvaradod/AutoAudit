# AutoAudit - interfaz web
# Proyecto Base de Datos 1
#
# Para correrla:  python3 app.py   y abrir http://localhost:5000
# Se entra con un usuario y contrasena de PostgreSQL.

import csv
import io
import secrets

import psycopg2
from flask import (Flask, Response, flash, redirect, render_template,
                   request, session, url_for)

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)

# Aqui se guardan los datos de conexion de cada persona que inicio sesion.
# (en la cookie solo va un codigo, no la contrasena)
sesiones = {}

EVENTOS = ['INSERT', 'UPDATE', 'DELETE']
MAX_FILAS = 500


# ---------------------------------------------------------------
# Conexion a la base de datos
# ---------------------------------------------------------------
def conectar():
    """Abre una conexion con los datos del usuario que inicio sesion."""
    datos = sesiones.get(session.get('codigo'))
    if datos is None:
        return None
    return psycopg2.connect(
        host=datos['host'], port=datos['puerto'], dbname=datos['bd'],
        user=datos['usuario'], password=datos['clave'],
        application_name='AutoAudit-web', connect_timeout=5)


def mensaje_error(e):
    """Deja solo la primera linea del error de PostgreSQL."""
    texto = str(e).strip()
    return texto.splitlines()[0] if texto else 'Error desconocido'


def requiere_login(funcion):
    """Si no hay sesion, manda a la pantalla de login."""
    def revisar(*args, **kwargs):
        if session.get('codigo') not in sesiones:
            return redirect(url_for('login'))
        return funcion(*args, **kwargs)
    revisar.__name__ = funcion.__name__
    return revisar


# ---------------------------------------------------------------
# Login
# ---------------------------------------------------------------
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        datos = {
            'host': request.form['host'].strip() or 'localhost',
            'puerto': request.form['puerto'].strip() or '5432',
            'bd': request.form['bd'].strip(),
            'usuario': request.form['usuario'].strip(),
            'clave': request.form['clave'],
        }
        try:
            con = psycopg2.connect(
                host=datos['host'], port=datos['puerto'], dbname=datos['bd'],
                user=datos['usuario'], password=datos['clave'],
                application_name='AutoAudit-web', connect_timeout=5)
            con.close()
        except psycopg2.Error as e:
            flash('No se pudo conectar: ' + mensaje_error(e), 'error')
            return render_template('login.html', datos=datos)

        codigo = secrets.token_hex(16)
        sesiones[codigo] = datos
        session['codigo'] = codigo
        session['usuario'] = datos['usuario']
        return redirect(url_for('configurar'))

    return render_template('login.html', datos={
        'host': 'localhost', 'puerto': '5432', 'bd': 'autoaudit_bd', 'usuario': ''})


@app.route('/logout')
def logout():
    sesiones.pop(session.get('codigo'), None)
    session.clear()
    return redirect(url_for('login'))


@app.route('/')
def inicio():
    return redirect(url_for('configurar'))


# ---------------------------------------------------------------
# Configurar auditoria
# ---------------------------------------------------------------
@app.route('/configurar', methods=['GET', 'POST'])
@requiere_login
def configurar():
    tabla_elegida = request.values.get('tabla', '')   # formato esquema.tabla
    codigo_generado = None
    tablas, columnas, activos = [], [], set()
    con = conectar()
    try:
        cur = con.cursor()

        # tablas que se pueden auditar (viene del diccionario de datos)
        cur.execute("SELECT esquema, nombre_tabla FROM auditoria.vw_tablas_disponibles "
                    "ORDER BY esquema, nombre_tabla")
        tablas = [e + '.' + t for e, t in cur.fetchall()]

        if tabla_elegida in tablas:
            esquema, tabla = tabla_elegida.split('.', 1)

            cur.execute("SELECT nombre_columna, tipo_dato "
                        "FROM auditoria.vw_columnas_disponibles "
                        "WHERE esquema = %s AND nombre_tabla = %s ORDER BY posicion",
                        (esquema, tabla))
            columnas = cur.fetchall()

            # si se mando el formulario, se guardan los cambios
            if request.method == 'POST':
                try:
                    marcados = set(request.form.getlist('marca'))   # 'columna|EVENTO'
                    if request.form.get('accion') == 'quitar':
                        marcados = set()

                    cur.execute("SELECT nombre_columna, evento "
                                "FROM auditoria.vw_configuracion_actual "
                                "WHERE esquema = %s AND nombre_tabla = %s AND activo",
                                (esquema, tabla))
                    antes = {c + '|' + e for c, e in cur.fetchall()}

                    for item in marcados - antes:
                        col, evento = item.split('|')
                        cur.execute("SELECT auditoria.agregar_configuracion(%s,%s,%s,%s)",
                                    (esquema, tabla, col, evento))
                    for item in antes - marcados:
                        col, evento = item.split('|')
                        cur.execute("SELECT auditoria.desactivar_configuracion(%s,%s,%s,%s)",
                                    (esquema, tabla, col, evento))

                    if marcados or antes:
                        cur.execute("SELECT auditoria.generar_trigger(%s,%s)", (esquema, tabla))
                        codigo_generado = cur.fetchone()[0]
                    con.commit()
                    flash('Configuracion guardada.', 'ok')
                except psycopg2.Error as e:
                    con.rollback()
                    flash('Error: ' + mensaje_error(e), 'error')
                    cur = con.cursor()

            # estado actual (para marcar las casillas)
            cur.execute("SELECT nombre_columna, evento FROM auditoria.vw_configuracion_actual "
                        "WHERE esquema = %s AND nombre_tabla = %s AND activo",
                        (esquema, tabla))
            activos = {c + '|' + e for c, e in cur.fetchall()}
    except psycopg2.Error as e:
        con.rollback()
        flash('Error: ' + mensaje_error(e), 'error')
    finally:
        con.close()

    return render_template('configurar.html', tablas=tablas, tabla=tabla_elegida,
                           columnas=columnas, activos=activos, eventos=EVENTOS,
                           codigo=codigo_generado)


# ---------------------------------------------------------------
# Ver configuracion actual
# ---------------------------------------------------------------
@app.route('/configuracion')
@requiere_login
def configuracion():
    filas = []
    con = conectar()
    try:
        cur = con.cursor()
        cur.execute("SELECT t.esquema, t.nombre_tabla, t.activa, "
                    "       string_agg(DISTINCT v.nombre_columna, ', ' ORDER BY v.nombre_columna) AS columnas, "
                    "       string_agg(DISTINCT v.evento, ', ' ORDER BY v.evento) AS eventos "
                    "FROM auditoria.tabla_auditada t "
                    "LEFT JOIN auditoria.vw_configuracion_actual v "
                    "  ON v.esquema = t.esquema AND v.nombre_tabla = t.nombre_tabla AND v.activo "
                    "GROUP BY t.esquema, t.nombre_tabla, t.activa "
                    "ORDER BY t.esquema, t.nombre_tabla")
        filas = cur.fetchall()
    except psycopg2.Error as e:
        flash('Error: ' + mensaje_error(e), 'error')
    finally:
        con.close()
    return render_template('configuracion.html', filas=filas)


# ---------------------------------------------------------------
# Historial
# ---------------------------------------------------------------
def buscar_historial(cur, filtros, limite=None):
    """Llama a las funciones historial_por_usuario / historial_por_columna."""
    desde = filtros['desde'] or None
    hasta = filtros['hasta'] or None
    if filtros['tipo'] == 'usuario':
        sql = "SELECT * FROM auditoria.historial_por_usuario(%s, %s, %s)"
        params = [filtros['usuario'], desde, hasta]
    else:
        esquema, tabla, columna = filtros['columna'].split('.')
        sql = "SELECT * FROM auditoria.historial_por_columna(%s, %s, %s, %s, %s)"
        params = [esquema, tabla, columna, desde, hasta]
    if limite:
        sql += " LIMIT %s"
        params.append(limite)
    cur.execute(sql, params)
    return [d[0] for d in cur.description], cur.fetchall()


def leer_filtros():
    return {
        'tipo': request.args.get('tipo', 'usuario'),
        'usuario': request.args.get('usuario', ''),
        'columna': request.args.get('columna', ''),
        'desde': request.args.get('desde', ''),
        'hasta': request.args.get('hasta', ''),
    }


@app.route('/historial')
@requiere_login
def historial():
    filtros = leer_filtros()
    usuarios, columnas = [], []
    nombres, filas = [], []
    buscado = 'buscar' in request.args
    hay_mas = False

    con = conectar()
    try:
        cur = con.cursor()
        cur.execute("SELECT nombre_usuario FROM auditoria.usuario_auditado ORDER BY 1")
        usuarios = [f[0] for f in cur.fetchall()]
        cur.execute("SELECT DISTINCT esquema || '.' || nombre_tabla || '.' || nombre_columna "
                    "FROM auditoria.vw_configuracion_actual ORDER BY 1")
        columnas = [f[0] for f in cur.fetchall()]

        if buscado:
            if (filtros['tipo'] == 'usuario' and not filtros['usuario']) or \
               (filtros['tipo'] == 'columna' and not filtros['columna']):
                flash('Escoge un usuario o una columna.', 'error')
            else:
                nombres, filas = buscar_historial(cur, filtros, MAX_FILAS + 1)
                if len(filas) > MAX_FILAS:
                    hay_mas = True
                    filas = filas[:MAX_FILAS]
    except psycopg2.Error as e:
        flash('Error: ' + mensaje_error(e), 'error')
    finally:
        con.close()

    return render_template('historial.html', f=filtros, usuarios=usuarios,
                           columnas=columnas, nombres=nombres, filas=filas,
                           buscado=buscado, hay_mas=hay_mas, maximo=MAX_FILAS)


@app.route('/historial/csv')
@requiere_login
def historial_csv():
    filtros = leer_filtros()
    con = conectar()
    try:
        cur = con.cursor()
        nombres, filas = buscar_historial(cur, filtros)
    except psycopg2.Error as e:
        flash('Error: ' + mensaje_error(e), 'error')
        return redirect(url_for('historial'))
    finally:
        con.close()

    salida = io.StringIO()
    escritor = csv.writer(salida)
    escritor.writerow(nombres)
    escritor.writerows(filas)
    return Response(salida.getvalue(), mimetype='text/csv',
                    headers={'Content-Disposition': 'attachment; filename=reporte_auditoria.csv'})


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
