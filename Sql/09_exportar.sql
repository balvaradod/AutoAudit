-- =====================================================
-- Script 09: exportar reportes a CSV (formato estandar)
-- Se ejecuta con psql; los archivos quedan en la carpeta donde se corre
-- Uso:
--   psql -d mi_bd -v usuario=postgres -v esquema=public -v tabla=cliente -v columna=saldo -f 09_exportar.sql
-- =====================================================
\o reporte_usuario.csv
COPY (SELECT * FROM auditoria.historial_por_usuario(:'usuario')) TO STDOUT WITH CSV HEADER;
\o reporte_columna.csv
COPY (SELECT * FROM auditoria.historial_por_columna(:'esquema', :'tabla', :'columna')) TO STDOUT WITH CSV HEADER;
\o
