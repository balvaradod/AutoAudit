-- =====================================================
-- Script 06: tablas de ejemplo para probar
-- =====================================================
DROP TABLE IF EXISTS public.cliente CASCADE;

CREATE TABLE public.cliente (
    id_cliente SERIAL PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL,
    correo     VARCHAR(100),
    saldo      NUMERIC(10,2) DEFAULT 0
);
