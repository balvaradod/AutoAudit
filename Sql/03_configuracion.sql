-- =====================================================
-- Script 03: configuracion de la auditoria
-- Solo usuarios administradores pueden usar estas funciones
-- =====================================================

-- Revisa si el usuario conectado es administrador
CREATE OR REPLACE FUNCTION auditoria.es_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN pg_has_role(session_user, 'auditoria_admin', 'member')
        OR (SELECT rolsuper FROM pg_roles WHERE rolname = session_user);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION auditoria.validar_admin()
RETURNS VOID AS $$
BEGIN
    IF NOT auditoria.es_admin() THEN
        RAISE EXCEPTION 'Solo un administrador puede configurar la auditoria';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Agrega (o vuelve a activar) una configuracion: tabla + columna + evento
CREATE OR REPLACE FUNCTION auditoria.agregar_configuracion(
    p_esquema TEXT, p_tabla TEXT, p_columna TEXT, p_evento TEXT)
RETURNS VOID AS $$
DECLARE
    v_evento     TEXT := upper(p_evento);
    v_id_tabla   INT;
    v_id_columna INT;
    v_id_evento  INT;
BEGIN
    PERFORM auditoria.validar_admin();

    -- validar que el evento sea correcto
    SELECT id_evento INTO v_id_evento FROM auditoria.evento WHERE nombre = v_evento;
    IF v_id_evento IS NULL THEN
        RAISE EXCEPTION 'Evento % no valido (use INSERT, UPDATE o DELETE)', p_evento;
    END IF;

    -- validar que la tabla exista
    IF NOT EXISTS (SELECT 1 FROM auditoria.vw_tablas_disponibles
                   WHERE esquema = p_esquema AND nombre_tabla = p_tabla) THEN
        RAISE EXCEPTION 'La tabla %.% no existe o no se puede auditar', p_esquema, p_tabla;
    END IF;

    -- validar que la columna exista
    IF NOT EXISTS (SELECT 1 FROM auditoria.vw_columnas_disponibles
                   WHERE esquema = p_esquema AND nombre_tabla = p_tabla
                     AND nombre_columna = p_columna) THEN
        RAISE EXCEPTION 'La columna % no existe en la tabla %.%', p_columna, p_esquema, p_tabla;
    END IF;

    -- tabla
    SELECT id_tabla INTO v_id_tabla FROM auditoria.tabla_auditada
    WHERE esquema = p_esquema AND nombre_tabla = p_tabla;
    IF v_id_tabla IS NULL THEN
        INSERT INTO auditoria.tabla_auditada (esquema, nombre_tabla)
        VALUES (p_esquema, p_tabla) RETURNING id_tabla INTO v_id_tabla;
    ELSE
        UPDATE auditoria.tabla_auditada SET activa = TRUE WHERE id_tabla = v_id_tabla;
    END IF;

    -- columna
    SELECT id_columna INTO v_id_columna FROM auditoria.columna_auditada
    WHERE id_tabla = v_id_tabla AND nombre_columna = p_columna;
    IF v_id_columna IS NULL THEN
        INSERT INTO auditoria.columna_auditada (id_tabla, nombre_columna)
        VALUES (v_id_tabla, p_columna) RETURNING id_columna INTO v_id_columna;
    END IF;

    -- configuracion (si ya existe solo se activa)
    INSERT INTO auditoria.configuracion_auditoria (id_columna, id_evento, activo)
    VALUES (v_id_columna, v_id_evento, TRUE)
    ON CONFLICT (id_columna, id_evento)
    DO UPDATE SET activo = TRUE, fecha_cambio = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Desactiva una configuracion (no se borra porque la bitacora la usa)
CREATE OR REPLACE FUNCTION auditoria.desactivar_configuracion(
    p_esquema TEXT, p_tabla TEXT, p_columna TEXT, p_evento TEXT)
RETURNS VOID AS $$
BEGIN
    PERFORM auditoria.validar_admin();

    UPDATE auditoria.configuracion_auditoria c
    SET activo = FALSE, fecha_cambio = now()
    FROM auditoria.columna_auditada col, auditoria.tabla_auditada t, auditoria.evento e
    WHERE c.id_columna = col.id_columna
      AND col.id_tabla = t.id_tabla
      AND c.id_evento = e.id_evento
      AND t.esquema = p_esquema AND t.nombre_tabla = p_tabla
      AND col.nombre_columna = p_columna
      AND e.nombre = upper(p_evento);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe esa configuracion';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Atajo: configura varias columnas y eventos de una tabla y genera el trigger
-- Si p_columnas es NULL se usan todas las columnas de la tabla
-- Si p_eventos es NULL se usan INSERT, UPDATE y DELETE
CREATE OR REPLACE FUNCTION auditoria.auditar_tabla(
    p_esquema TEXT, p_tabla TEXT,
    p_columnas TEXT[] DEFAULT NULL,
    p_eventos  TEXT[] DEFAULT ARRAY['INSERT','UPDATE','DELETE'])
RETURNS TEXT AS $$
DECLARE
    v_col TEXT;
    v_evt TEXT;
    v_lista TEXT[];
BEGIN
    PERFORM auditoria.validar_admin();

    IF p_columnas IS NULL THEN
        SELECT array_agg(nombre_columna ORDER BY posicion) INTO v_lista
        FROM auditoria.vw_columnas_disponibles
        WHERE esquema = p_esquema AND nombre_tabla = p_tabla;
    ELSE
        v_lista := p_columnas;
    END IF;

    IF v_lista IS NULL THEN
        RAISE EXCEPTION 'La tabla %.% no existe', p_esquema, p_tabla;
    END IF;

    FOREACH v_col IN ARRAY v_lista LOOP
        FOREACH v_evt IN ARRAY p_eventos LOOP
            PERFORM auditoria.agregar_configuracion(p_esquema, p_tabla, v_col, v_evt);
        END LOOP;
    END LOOP;

    RETURN auditoria.generar_trigger(p_esquema, p_tabla);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Vista para ver como esta la configuracion actual
CREATE OR REPLACE VIEW auditoria.vw_configuracion_actual AS
SELECT t.esquema, t.nombre_tabla, col.nombre_columna, e.nombre AS evento,
       c.activo, c.id_config
FROM auditoria.configuracion_auditoria c
JOIN auditoria.columna_auditada col ON col.id_columna = c.id_columna
JOIN auditoria.tabla_auditada t ON t.id_tabla = col.id_tabla
JOIN auditoria.evento e ON e.id_evento = c.id_evento;

GRANT SELECT ON auditoria.vw_tablas_disponibles, auditoria.vw_columnas_disponibles,
                auditoria.vw_llaves_primarias, auditoria.vw_configuracion_actual
      TO auditoria_admin;
GRANT EXECUTE ON FUNCTION auditoria.agregar_configuracion(TEXT,TEXT,TEXT,TEXT),
                          auditoria.desactivar_configuracion(TEXT,TEXT,TEXT,TEXT),
                          auditoria.auditar_tabla(TEXT,TEXT,TEXT[],TEXT[])
      TO auditoria_admin;
