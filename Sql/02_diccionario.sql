-- =====================================================
-- Script 02: consultas al diccionario de datos
-- (de aqui sale la lista de tablas y columnas para auditar)
-- =====================================================

-- Tablas que se pueden auditar (sin las del sistema ni las de auditoria)
CREATE OR REPLACE VIEW auditoria.vw_tablas_disponibles AS
SELECT table_schema AS esquema,
       table_name   AS nombre_tabla
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema', 'auditoria');

-- Columnas de esas tablas
CREATE OR REPLACE VIEW auditoria.vw_columnas_disponibles AS
SELECT c.table_schema AS esquema,
       c.table_name   AS nombre_tabla,
       c.column_name  AS nombre_columna,
       c.data_type    AS tipo_dato,
       c.is_nullable  AS acepta_nulos,
       c.ordinal_position AS posicion
FROM information_schema.columns c
JOIN auditoria.vw_tablas_disponibles t
  ON t.esquema = c.table_schema AND t.nombre_tabla = c.table_name;

-- Llaves primarias de las tablas
CREATE OR REPLACE VIEW auditoria.vw_llaves_primarias AS
SELECT kcu.table_schema AS esquema,
       kcu.table_name   AS nombre_tabla,
       kcu.column_name  AS nombre_columna,
       kcu.ordinal_position AS posicion
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema = kcu.table_schema
WHERE tc.constraint_type = 'PRIMARY KEY';

-- Ejemplos de uso:
--   SELECT * FROM auditoria.vw_tablas_disponibles;
--   SELECT * FROM auditoria.vw_columnas_disponibles WHERE nombre_tabla = 'cliente';
