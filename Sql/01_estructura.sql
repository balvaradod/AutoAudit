-- =====================================================
-- AutoAudit - Proyecto Base de Datos 1
-- Script 01: creacion de la estructura del sistema
-- Base de datos: PostgreSQL
-- =====================================================

-- rol que puede configurar la auditoria
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auditoria_admin') THEN
        CREATE ROLE auditoria_admin;
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS auditoria;

-- -----------------------------------------------------
-- Tablas auditadas (las tablas que el usuario escoge)
-- -----------------------------------------------------
CREATE TABLE auditoria.tabla_auditada (
    id_tabla      SERIAL PRIMARY KEY,
    esquema       VARCHAR(63) NOT NULL,
    nombre_tabla  VARCHAR(63) NOT NULL,
    activa        BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT uq_tabla_auditada UNIQUE (esquema, nombre_tabla)
);

-- -----------------------------------------------------
-- Columnas auditadas (columnas de cada tabla)
-- -----------------------------------------------------
CREATE TABLE auditoria.columna_auditada (
    id_columna     SERIAL PRIMARY KEY,
    id_tabla       INT NOT NULL REFERENCES auditoria.tabla_auditada(id_tabla),
    nombre_columna VARCHAR(63) NOT NULL,
    CONSTRAINT uq_columna_auditada UNIQUE (id_tabla, nombre_columna)
);

-- -----------------------------------------------------
-- Eventos (INSERT, UPDATE, DELETE)
-- -----------------------------------------------------
CREATE TABLE auditoria.evento (
    id_evento SERIAL PRIMARY KEY,
    nombre    VARCHAR(10) NOT NULL UNIQUE,
    CONSTRAINT ck_evento_nombre CHECK (nombre IN ('INSERT', 'UPDATE', 'DELETE'))
);

INSERT INTO auditoria.evento (nombre) VALUES ('INSERT'), ('UPDATE'), ('DELETE');

-- -----------------------------------------------------
-- Configuracion de auditoria
-- Dice que evento se audita en cada columna
-- -----------------------------------------------------
CREATE TABLE auditoria.configuracion_auditoria (
    id_config   SERIAL PRIMARY KEY,
    id_columna  INT NOT NULL REFERENCES auditoria.columna_auditada(id_columna),
    id_evento   INT NOT NULL REFERENCES auditoria.evento(id_evento),
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_cambio TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT uq_configuracion UNIQUE (id_columna, id_evento)
);

-- -----------------------------------------------------
-- Usuarios auditados
-- -----------------------------------------------------
CREATE TABLE auditoria.usuario_auditado (
    id_usuario     SERIAL PRIMARY KEY,
    nombre_usuario VARCHAR(63) NOT NULL UNIQUE
);

-- -----------------------------------------------------
-- Estaciones de trabajo auditadas
-- -----------------------------------------------------
CREATE TABLE auditoria.estacion_trabajo (
    id_estacion SERIAL PRIMARY KEY,
    ip_origen   VARCHAR(45) NOT NULL UNIQUE,   -- 'local' si viene por socket
    nombre_host VARCHAR(100)
);

-- -----------------------------------------------------
-- Bitacora (una fila por cada columna que cambio)
-- No tiene FK a la tabla origen a proposito, para que
-- los datos se queden aunque se borre el registro original.
-- -----------------------------------------------------
CREATE TABLE auditoria.bitacora (
    id_bitacora    BIGSERIAL PRIMARY KEY,
    id_config      INT NOT NULL REFERENCES auditoria.configuracion_auditoria(id_config),
    id_usuario     INT NOT NULL REFERENCES auditoria.usuario_auditado(id_usuario),
    id_estacion    INT NOT NULL REFERENCES auditoria.estacion_trabajo(id_estacion),
    fecha_hora     TIMESTAMP NOT NULL DEFAULT now(),
    registro_pk    VARCHAR(200) NOT NULL,      -- llave primaria del registro cambiado
    valor_anterior TEXT,
    valor_nuevo    TEXT
);

CREATE INDEX idx_bitacora_usuario ON auditoria.bitacora (id_usuario, fecha_hora);
CREATE INDEX idx_bitacora_config  ON auditoria.bitacora (id_config, fecha_hora);

-- -----------------------------------------------------
-- Seguridad: la bitacora no se puede modificar a mano
-- -----------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA auditoria FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA auditoria FROM PUBLIC;
GRANT USAGE ON SCHEMA auditoria TO auditoria_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA auditoria TO auditoria_admin;
-- nadie (salvo el dueno por los triggers) tiene INSERT/UPDATE/DELETE en bitacora

CREATE OR REPLACE FUNCTION auditoria.bloquear_cambios_bitacora()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'La bitacora no se puede modificar ni borrar';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bitacora_protegida
BEFORE UPDATE OR DELETE ON auditoria.bitacora
FOR EACH ROW EXECUTE FUNCTION auditoria.bloquear_cambios_bitacora();
