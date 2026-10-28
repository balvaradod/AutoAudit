-- =====================================================
-- Script 08: prueba de rendimiento
-- Compara insertar N filas SIN auditoria y CON auditoria
-- =====================================================
\set ON_ERROR_STOP on
\timing off

DROP TABLE IF EXISTS public.prueba_rendimiento;
CREATE TABLE public.prueba_rendimiento (
    id     SERIAL PRIMARY KEY,
    texto  VARCHAR(50),
    numero INT
);

CREATE TABLE IF NOT EXISTS public.resultado_rendimiento (
    cantidad INT, con_auditoria BOOLEAN, segundos NUMERIC(10,3)
);
TRUNCATE public.resultado_rendimiento;

DO $$
DECLARE
    v_cantidades INT[] := ARRAY[1000, 10000, 50000, 100000];
    v_n INT;
    v_inicio TIMESTAMP;
    v_seg NUMERIC;
BEGIN
    FOREACH v_n IN ARRAY v_cantidades LOOP
        -- sin auditoria
        PERFORM auditoria.quitar_trigger('public', 'prueba_rendimiento');
        TRUNCATE public.prueba_rendimiento RESTART IDENTITY;
        v_inicio := clock_timestamp();
        INSERT INTO public.prueba_rendimiento (texto, numero)
        SELECT 'texto ' || g, g FROM generate_series(1, v_n) g;
        v_seg := extract(epoch FROM clock_timestamp() - v_inicio);
        INSERT INTO public.resultado_rendimiento VALUES (v_n, FALSE, v_seg);

        -- con auditoria
        PERFORM auditoria.auditar_tabla('public', 'prueba_rendimiento',
                ARRAY['texto','numero'], ARRAY['INSERT','UPDATE','DELETE']);
        TRUNCATE public.prueba_rendimiento RESTART IDENTITY;
        v_inicio := clock_timestamp();
        INSERT INTO public.prueba_rendimiento (texto, numero)
        SELECT 'texto ' || g, g FROM generate_series(1, v_n) g;
        v_seg := extract(epoch FROM clock_timestamp() - v_inicio);
        INSERT INTO public.resultado_rendimiento VALUES (v_n, TRUE, v_seg);
    END LOOP;
END $$;

-- Resultados: tiempo y cuanto mas tarda con auditoria
SELECT s.cantidad,
       s.segundos AS seg_sin_auditoria,
       c.segundos AS seg_con_auditoria,
       round(c.segundos / s.segundos, 2) AS veces_mas_lento
FROM public.resultado_rendimiento s
JOIN public.resultado_rendimiento c ON c.cantidad = s.cantidad AND c.con_auditoria
WHERE NOT s.con_auditoria
ORDER BY s.cantidad;

-- Tambien se mide una consulta sobre la bitacora ya grande
\timing on
SELECT count(*) FROM auditoria.historial_por_usuario(session_user::text);
\timing off
