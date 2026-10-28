-- =====================================================
-- Script 04: generacion dinamica de triggers
-- =====================================================

-- Buscan (o crean) el usuario y la estacion de quien hace el cambio
CREATE OR REPLACE FUNCTION auditoria.obtener_usuario()
RETURNS INT AS $$
DECLARE
    v_id INT;
BEGIN
    SELECT id_usuario INTO v_id FROM auditoria.usuario_auditado
    WHERE nombre_usuario = session_user;
    IF v_id IS NULL THEN
        INSERT INTO auditoria.usuario_auditado (nombre_usuario)
        VALUES (session_user)
        ON CONFLICT (nombre_usuario) DO NOTHING;
        SELECT id_usuario INTO v_id FROM auditoria.usuario_auditado
        WHERE nombre_usuario = session_user;
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION auditoria.obtener_estacion()
RETURNS INT AS $$
DECLARE
    v_id INT;
    v_ip TEXT := COALESCE(host(inet_client_addr()), 'local');
BEGIN
    SELECT id_estacion INTO v_id FROM auditoria.estacion_trabajo
    WHERE ip_origen = v_ip;
    IF v_id IS NULL THEN
        INSERT INTO auditoria.estacion_trabajo (ip_origen, nombre_host)
        VALUES (v_ip, current_setting('application_name', true))
        ON CONFLICT (ip_origen) DO NOTHING;
        SELECT id_estacion INTO v_id FROM auditoria.estacion_trabajo
        WHERE ip_origen = v_ip;
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- -----------------------------------------------------
-- Genera la funcion y el trigger de UNA tabla segun la configuracion.
-- Se puede volver a ejecutar cada vez que cambie la configuracion.
-- Devuelve el codigo SQL que se genero.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.generar_trigger(p_esquema TEXT, p_tabla TEXT)
RETURNS TEXT AS $$
DECLARE
    v_id_tabla   INT;
    v_pk         TEXT;
    v_nombre_fn  TEXT;
    v_nombre_trg TEXT;
    v_cod_ins    TEXT := '';
    v_cod_upd    TEXT := '';
    v_cod_del    TEXT := '';
    v_eventos    TEXT := '';
    v_funcion    TEXT;
    v_trigger    TEXT;
    r            RECORD;
BEGIN
    PERFORM auditoria.validar_admin();

    -- la tabla tiene que existir de verdad
    IF to_regclass(format('%I.%I', p_esquema, p_tabla)) IS NULL THEN
        RAISE EXCEPTION 'La tabla %.% no existe', p_esquema, p_tabla;
    END IF;

    SELECT id_tabla INTO v_id_tabla FROM auditoria.tabla_auditada
    WHERE esquema = p_esquema AND nombre_tabla = p_tabla;
    IF v_id_tabla IS NULL THEN
        RAISE EXCEPTION 'La tabla %.% no tiene configuracion de auditoria', p_esquema, p_tabla;
    END IF;

    v_nombre_fn  := format('fn_audit_%s_%s', p_esquema, p_tabla);
    v_nombre_trg := format('trg_audit_%s_%s', p_esquema, p_tabla);

    -- llave primaria (para saber cual registro cambio)
    SELECT string_agg(format('v_fila->>%L', nombre_columna), ', ' ORDER BY posicion)
    INTO v_pk
    FROM auditoria.vw_llaves_primarias
    WHERE esquema = p_esquema AND nombre_tabla = p_tabla;

    IF v_pk IS NULL THEN
        RAISE EXCEPTION 'La tabla %.% necesita llave primaria para ser auditada', p_esquema, p_tabla;
    END IF;

    -- armar el codigo de cada columna configurada y activa
    FOR r IN
        SELECT c.id_config, col.nombre_columna, e.nombre AS evento
        FROM auditoria.configuracion_auditoria c
        JOIN auditoria.columna_auditada col ON col.id_columna = c.id_columna
        JOIN auditoria.evento e ON e.id_evento = c.id_evento
        WHERE col.id_tabla = v_id_tabla AND c.activo
        ORDER BY c.id_config
    LOOP
        -- por si borraron la columna de la tabla despues de configurarla
        IF NOT EXISTS (SELECT 1 FROM auditoria.vw_columnas_disponibles
                       WHERE esquema = p_esquema AND nombre_tabla = p_tabla
                         AND nombre_columna = r.nombre_columna) THEN
            RAISE EXCEPTION 'La columna % ya no existe en %.%', r.nombre_columna, p_esquema, p_tabla;
        END IF;

        IF r.evento = 'INSERT' THEN
            v_cod_ins := v_cod_ins || format(
              E'        INSERT INTO auditoria.bitacora (id_config, id_usuario, id_estacion, registro_pk, valor_anterior, valor_nuevo)\n'
              '        VALUES (%s, v_usuario, v_estacion, v_pk, NULL, v_nuevo->>%L);\n',
              r.id_config, r.nombre_columna);
        ELSIF r.evento = 'UPDATE' THEN
            v_cod_upd := v_cod_upd || format(
              E'        IF (v_viejo->>%L) IS DISTINCT FROM (v_nuevo->>%L) THEN\n'
              '            INSERT INTO auditoria.bitacora (id_config, id_usuario, id_estacion, registro_pk, valor_anterior, valor_nuevo)\n'
              '            VALUES (%s, v_usuario, v_estacion, v_pk, v_viejo->>%L, v_nuevo->>%L);\n'
              '        END IF;\n',
              r.nombre_columna, r.nombre_columna, r.id_config, r.nombre_columna, r.nombre_columna);
        ELSE
            v_cod_del := v_cod_del || format(
              E'        INSERT INTO auditoria.bitacora (id_config, id_usuario, id_estacion, registro_pk, valor_anterior, valor_nuevo)\n'
              '        VALUES (%s, v_usuario, v_estacion, v_pk, v_viejo->>%L, NULL);\n',
              r.id_config, r.nombre_columna);
        END IF;
    END LOOP;

    -- eventos que va a tener el trigger
    IF v_cod_ins <> '' THEN v_eventos := v_eventos || ' INSERT'; END IF;
    IF v_cod_upd <> '' THEN v_eventos := v_eventos || CASE WHEN v_eventos <> '' THEN ' OR' ELSE '' END || ' UPDATE'; END IF;
    IF v_cod_del <> '' THEN v_eventos := v_eventos || CASE WHEN v_eventos <> '' THEN ' OR' ELSE '' END || ' DELETE'; END IF;

    -- si no hay nada activo se quita el trigger
    IF v_eventos = '' THEN
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I', v_nombre_trg, p_esquema, p_tabla);
        EXECUTE format('DROP FUNCTION IF EXISTS auditoria.%I()', v_nombre_fn);
        UPDATE auditoria.tabla_auditada SET activa = FALSE WHERE id_tabla = v_id_tabla;
        RETURN 'Sin configuracion activa: se elimino el trigger de ' || p_esquema || '.' || p_tabla;
    END IF;

    -- funcion del trigger
    v_funcion := format(
      E'CREATE OR REPLACE FUNCTION auditoria.%I() RETURNS TRIGGER AS $f$\n'
      'DECLARE\n'
      '    v_nuevo JSONB;\n'
      '    v_viejo JSONB;\n'
      '    v_fila JSONB;\n'
      '    v_pk TEXT;\n'
      '    v_usuario INT;\n'
      '    v_estacion INT;\n'
      'BEGIN\n'
      '    IF TG_OP <> ''DELETE'' THEN v_nuevo := to_jsonb(NEW); END IF;\n'
      '    IF TG_OP <> ''INSERT'' THEN v_viejo := to_jsonb(OLD); END IF;\n'
      '    v_fila := COALESCE(v_nuevo, v_viejo);\n'
      '    v_pk := concat_ws(''-'', %s);\n'
      '    v_usuario := auditoria.obtener_usuario();\n'
      '    v_estacion := auditoria.obtener_estacion();\n'
      '\n'
      '    IF TG_OP = ''INSERT'' THEN\n%s    ELSIF TG_OP = ''UPDATE'' THEN\n%s    ELSIF TG_OP = ''DELETE'' THEN\n%s    END IF;\n'
      '    RETURN NULL;\n'
      'END;\n'
      '$f$ LANGUAGE plpgsql SECURITY DEFINER;',
      v_nombre_fn, v_pk,
      COALESCE(NULLIF(v_cod_ins, ''), E'        NULL;\n'),
      COALESCE(NULLIF(v_cod_upd, ''), E'        NULL;\n'),
      COALESCE(NULLIF(v_cod_del, ''), E'        NULL;\n'));

    -- trigger AFTER, un solo trigger por tabla
    v_trigger := format(
      'CREATE TRIGGER %I AFTER%s ON %I.%I FOR EACH ROW EXECUTE FUNCTION auditoria.%I()',
      v_nombre_trg, v_eventos, p_esquema, p_tabla, v_nombre_fn);

    BEGIN
        EXECUTE v_funcion;
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I', v_nombre_trg, p_esquema, p_tabla);
        EXECUTE v_trigger;
        UPDATE auditoria.tabla_auditada SET activa = TRUE WHERE id_tabla = v_id_tabla;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al generar el trigger de %.%: %', p_esquema, p_tabla, SQLERRM;
    END;

    RETURN v_funcion || E'\n\n' || v_trigger || ';';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Quita el trigger de una tabla y la marca como no activa
CREATE OR REPLACE FUNCTION auditoria.quitar_trigger(p_esquema TEXT, p_tabla TEXT)
RETURNS VOID AS $$
BEGIN
    PERFORM auditoria.validar_admin();
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
                   format('trg_audit_%s_%s', p_esquema, p_tabla), p_esquema, p_tabla);
    EXECUTE format('DROP FUNCTION IF EXISTS auditoria.%I()',
                   format('fn_audit_%s_%s', p_esquema, p_tabla));
    UPDATE auditoria.tabla_auditada SET activa = FALSE
    WHERE esquema = p_esquema AND nombre_tabla = p_tabla;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION auditoria.generar_trigger(TEXT,TEXT),
                          auditoria.quitar_trigger(TEXT,TEXT)
      TO auditoria_admin;
