-- =====================================================
-- Script 07: pruebas funcionales
-- Ejecutar despues de los scripts 01 al 06
-- =====================================================
\set ON_ERROR_STOP on

-- Configuracion: auditar cliente (nombre, correo, saldo) en los 3 eventos
SELECT auditoria.auditar_tabla('public', 'cliente',
       ARRAY['nombre','correo','saldo'], ARRAY['INSERT','UPDATE','DELETE']);

-- -----------------------------------------------------
-- Prueba 1: INSERT
-- -----------------------------------------------------
INSERT INTO public.cliente (nombre, correo, saldo) VALUES ('Juan Perez', 'juan@mail.com', 100);

DO $$
DECLARE v_total INT;
BEGIN
    SELECT count(*) INTO v_total FROM auditoria.vw_bitacora_detalle
    WHERE nombre_tabla = 'cliente' AND evento = 'INSERT' AND registro_pk = '1';
    IF v_total = 3 THEN
        RAISE NOTICE 'PRUEBA 1 (insert): OK - 3 columnas registradas';
    ELSE
        RAISE EXCEPTION 'PRUEBA 1 (insert): FALLO - se esperaban 3 filas y hay %', v_total;
    END IF;
END $$;

-- -----------------------------------------------------
-- Prueba 2: UPDATE (valor anterior y nuevo)
-- -----------------------------------------------------
UPDATE public.cliente SET saldo = 250.50 WHERE id_cliente = 1;

DO $$
DECLARE v_ant TEXT; v_nue TEXT; v_total INT;
BEGIN
    SELECT valor_anterior, valor_nuevo INTO v_ant, v_nue
    FROM auditoria.vw_bitacora_detalle
    WHERE nombre_tabla = 'cliente' AND evento = 'UPDATE' AND nombre_columna = 'saldo';

    -- solo cambio saldo, entonces nombre y correo no deben aparecer
    SELECT count(*) INTO v_total FROM auditoria.vw_bitacora_detalle WHERE evento = 'UPDATE';

    IF v_ant = '100.00' AND v_nue = '250.50' AND v_total = 1 THEN
        RAISE NOTICE 'PRUEBA 2 (update): OK - % -> %', v_ant, v_nue;
    ELSE
        RAISE EXCEPTION 'PRUEBA 2 (update): FALLO - ant=%, nuevo=%, filas=%', v_ant, v_nue, v_total;
    END IF;
END $$;

-- -----------------------------------------------------
-- Prueba 3: DELETE (los datos se quedan en la bitacora)
-- -----------------------------------------------------
DELETE FROM public.cliente WHERE id_cliente = 1;

DO $$
DECLARE v_total INT; v_nombre TEXT;
BEGIN
    SELECT count(*) INTO v_total FROM public.cliente WHERE id_cliente = 1;
    IF v_total <> 0 THEN RAISE EXCEPTION 'PRUEBA 3: el registro no se borro'; END IF;

    SELECT valor_anterior INTO v_nombre FROM auditoria.vw_bitacora_detalle
    WHERE evento = 'DELETE' AND nombre_columna = 'nombre' AND registro_pk = '1';

    IF v_nombre = 'Juan Perez' THEN
        RAISE NOTICE 'PRUEBA 3 (delete): OK - la bitacora conserva "%"', v_nombre;
    ELSE
        RAISE EXCEPTION 'PRUEBA 3 (delete): FALLO';
    END IF;
END $$;

-- -----------------------------------------------------
-- Prueba 4: la bitacora no se puede modificar
-- -----------------------------------------------------
DO $$
BEGIN
    BEGIN
        UPDATE auditoria.bitacora SET valor_nuevo = 'hackeado' WHERE id_bitacora = 1;
        RAISE EXCEPTION 'PRUEBA 4: FALLO - se pudo modificar la bitacora';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'PRUEBA 4%' THEN RAISE; END IF;
        RAISE NOTICE 'PRUEBA 4 (bitacora protegida): OK';
    END;
END $$;

-- -----------------------------------------------------
-- Prueba 5: validaciones (tabla, columna y evento que no existen)
-- -----------------------------------------------------
DO $$
BEGIN
    BEGIN
        PERFORM auditoria.agregar_configuracion('public', 'tabla_falsa', 'x', 'INSERT');
        RAISE EXCEPTION 'PRUEBA 5: FALLO tabla falsa';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'PRUEBA 5%' THEN RAISE; END IF;
    END;
    BEGIN
        PERFORM auditoria.agregar_configuracion('public', 'cliente', 'columna_falsa', 'INSERT');
        RAISE EXCEPTION 'PRUEBA 5: FALLO columna falsa';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'PRUEBA 5%' THEN RAISE; END IF;
    END;
    BEGIN
        PERFORM auditoria.agregar_configuracion('public', 'cliente', 'saldo', 'TRUNCATE');
        RAISE EXCEPTION 'PRUEBA 5: FALLO evento falso';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'PRUEBA 5%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PRUEBA 5 (validaciones): OK';
END $$;

-- -----------------------------------------------------
-- Prueba 6: desactivar una columna y regenerar el trigger
-- -----------------------------------------------------
SELECT auditoria.desactivar_configuracion('public', 'cliente', 'correo', 'UPDATE');
SELECT auditoria.generar_trigger('public', 'cliente') IS NOT NULL AS trigger_regenerado;

INSERT INTO public.cliente (nombre, correo, saldo) VALUES ('Maria Lopez', 'maria@mail.com', 50);
UPDATE public.cliente SET correo = 'maria2@mail.com' WHERE nombre = 'Maria Lopez';

DO $$
DECLARE v_total INT;
BEGIN
    SELECT count(*) INTO v_total FROM auditoria.vw_bitacora_detalle
    WHERE nombre_columna = 'correo' AND evento = 'UPDATE';
    IF v_total = 0 THEN
        RAISE NOTICE 'PRUEBA 6 (desactivar columna): OK';
    ELSE
        RAISE EXCEPTION 'PRUEBA 6: FALLO, se siguio auditando el correo';
    END IF;
END $$;

-- -----------------------------------------------------
-- Prueba 7: consultas de historial
-- -----------------------------------------------------
DO $$
DECLARE v_usuario INT; v_columna INT;
BEGIN
    SELECT count(*) INTO v_usuario FROM auditoria.historial_por_usuario(session_user::text);
    SELECT count(*) INTO v_columna FROM auditoria.historial_por_columna('public','cliente','saldo');
    IF v_usuario > 0 AND v_columna >= 3 THEN
        RAISE NOTICE 'PRUEBA 7 (consultas): OK - % cambios del usuario, % de la columna saldo', v_usuario, v_columna;
    ELSE
        RAISE EXCEPTION 'PRUEBA 7: FALLO';
    END IF;
END $$;

-- -----------------------------------------------------
-- Prueba 8: un usuario sin permisos no puede configurar
-- -----------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'usuario_normal') THEN
        CREATE ROLE usuario_normal LOGIN;
    END IF;
END $$;
GRANT USAGE ON SCHEMA auditoria TO usuario_normal;
GRANT EXECUTE ON FUNCTION auditoria.agregar_configuracion(TEXT,TEXT,TEXT,TEXT) TO usuario_normal;

SET SESSION AUTHORIZATION usuario_normal;
DO $$
BEGIN
    BEGIN
        PERFORM auditoria.agregar_configuracion('public', 'cliente', 'nombre', 'INSERT');
        RAISE EXCEPTION 'PRUEBA 8: FALLO - un usuario normal pudo configurar';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'PRUEBA 8%' THEN RAISE; END IF;
        RAISE NOTICE 'PRUEBA 8 (solo admin configura): OK';
    END;
    BEGIN
        INSERT INTO auditoria.bitacora (id_config, id_usuario, id_estacion, registro_pk)
        VALUES (1, 1, 1, 'x');
        RAISE EXCEPTION 'PRUEBA 8b: FALLO - escritura directa en bitacora';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PRUEBA 8b (sin escritura directa en bitacora): OK';
    END;
END $$;
RESET SESSION AUTHORIZATION;

-- Ver el resultado final
SELECT id_bitacora, fecha_hora, nombre_usuario, nombre_tabla, nombre_columna,
       evento, registro_pk, valor_anterior, valor_nuevo
FROM auditoria.vw_bitacora_detalle ORDER BY id_bitacora;
