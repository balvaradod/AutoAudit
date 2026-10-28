# AutoAudit - Sistema de auditoría automatizado
Proyecto del curso Base de Datos 1 - Universidad Mariano Gálvez

Sistema en PostgreSQL que genera triggers automáticamente para guardar los cambios
(insert, update, delete) de las tablas y columnas que el administrador escoja.

## Instalación
```bash
chmod +x instalar.sh
./instalar.sh autoaudit_bd        # sin sudo adelante, el script lo usa por dentro
cat sql/06_datos_prueba.sql sql/07_pruebas.sql | sudo -u postgres psql -d autoaudit_bd
```

## Uso rápido
```sql
SELECT * FROM auditoria.vw_tablas_disponibles;           -- tablas que se pueden auditar
SELECT auditoria.auditar_tabla('public', 'cliente',
       ARRAY['nombre','correo','saldo'], ARRAY['INSERT','UPDATE','DELETE']);
SELECT * FROM auditoria.historial_por_usuario('postgres');
SELECT * FROM auditoria.historial_por_columna('public', 'cliente', 'saldo');
```

## Interfaz web (Python + Flask)
```bash
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'una_clave';"
sudo apt install python3 python3-venv
cd interfaz
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 app.py
```
Abrir http://localhost:5000 y entrar con: servidor `localhost`, puerto `5432`,
base `autoaudit_bd`, usuario `postgres` y la contraseña de arriba.

## Archivos
| Carpeta/archivo | Contenido |
|---|---|
| sql/01_estructura.sql | Tablas del sistema y seguridad |
| sql/02_diccionario.sql | Consultas al diccionario de datos |
| sql/03_configuracion.sql | Funciones para configurar la auditoría |
| sql/04_generador_triggers.sql | Generación dinámica de triggers |
| sql/05_consultas.sql | Consultas de historial por usuario y columna |
| sql/06_datos_prueba.sql | Tabla de ejemplo |
| sql/07_pruebas.sql | Casos de prueba (insert, update, delete, seguridad) |
| sql/08_rendimiento.sql | Prueba de rendimiento |
| sql/09_exportar.sql | Exportar reportes a CSV |
| interfaz/ | Interfaz web (app.py, templates, requirements.txt) |
| docs/ | Documentación en PDF y diagrama ER |
