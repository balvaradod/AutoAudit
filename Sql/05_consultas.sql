-- =====================================================
-- Script 05: consultas de historial
-- =====================================================

-- Vista con todo ya unido (mas facil de leer)
CREATE OR REPLACE VIEW auditoria.vw_bitacora_detalle AS
SELECT b.id_bitacora,
       b.fecha_hora,
       u.nombre_usuario,
       es.ip_origen,
       es.nombre_host,
       t.esquema,
       t.nombre_tabla,
       col.nombre_columna,
       e.nombre AS evento,
       b.registro_pk,
       b.valor_anterior,
       b.valor_nuevo
FROM auditoria.bitacora b
JOIN auditoria.configuracion_auditoria c ON c.id_config = b.id_config
JOIN auditoria.columna_auditada col ON col.id_columna = c.id_columna
JOIN auditoria.tabla_auditada t ON t.id_tabla = col.id_tabla
JOIN auditoria.evento e ON e.id_evento = c.id_evento
JOIN auditoria.usuario_auditado u ON u.id_usuario = b.id_usuario
JOIN auditoria.estacion_trabajo es ON es.id_estacion = b.id_estacion;

-- Historial de un usuario (las fechas son opcionales)
CREATE OR REPLACE FUNCTION auditoria.historial_por_usuario(
    p_usuario TEXT,
    p_desde TIMESTAMP DEFAULT NULL,
    p_hasta TIMESTAMP DEFAULT NULL)
RETURNS SETOF auditoria.vw_bitacora_detalle AS $$
    SELECT *
    FROM auditoria.vw_bitacora_detalle
    WHERE nombre_usuario = p_usuario
      AND (p_desde IS NULL OR fecha_hora >= p_desde)
      AND (p_hasta IS NULL OR fecha_hora <= p_hasta)
    ORDER BY fecha_hora, id_bitacora;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Historial de una columna (las fechas son opcionales)
CREATE OR REPLACE FUNCTION auditoria.historial_por_columna(
    p_esquema TEXT, p_tabla TEXT, p_columna TEXT,
    p_desde TIMESTAMP DEFAULT NULL,
    p_hasta TIMESTAMP DEFAULT NULL)
RETURNS SETOF auditoria.vw_bitacora_detalle AS $$
    SELECT *
    FROM auditoria.vw_bitacora_detalle
    WHERE esquema = p_esquema
      AND nombre_tabla = p_tabla
      AND nombre_columna = p_columna
      AND (p_desde IS NULL OR fecha_hora >= p_desde)
      AND (p_hasta IS NULL OR fecha_hora <= p_hasta)
    ORDER BY fecha_hora, id_bitacora;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

GRANT SELECT ON auditoria.vw_bitacora_detalle TO auditoria_admin;
GRANT EXECUTE ON FUNCTION auditoria.historial_por_usuario(TEXT,TIMESTAMP,TIMESTAMP),
                          auditoria.historial_por_columna(TEXT,TEXT,TEXT,TIMESTAMP,TIMESTAMP)
      TO auditoria_admin;

-- Ejemplos:
--   SELECT * FROM auditoria.historial_por_usuario('postgres');
--   SELECT * FROM auditoria.historial_por_usuario('postgres', '2026-10-01', '2026-10-31');
--   SELECT * FROM auditoria.historial_por_columna('public', 'cliente', 'saldo');
