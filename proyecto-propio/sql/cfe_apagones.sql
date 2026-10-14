-- =====================================================================
-- Práctica 3 · Proyecto propio
-- Plataforma de monitoreo de infraestructura eléctrica y prevención
-- de apagones (CFE / CDMX)
-- =====================================================================

DROP DATABASE IF EXISTS cfe;
CREATE DATABASE cfe CHARACTER SET utf8mb4;
USE cfe;

-- ---------------------------------------------------------------------
-- 1. GEOGRAFÍA
-- ---------------------------------------------------------------------
CREATE TABLE alcaldia (
    id_alcaldia  SMALLINT     PRIMARY KEY,
    nombre       VARCHAR(60)  NOT NULL UNIQUE
);

-- Entidad débil por identificación (Regla 8): PK = FK del dueño + discriminador
CREATE TABLE colonia (
    id_alcaldia     SMALLINT     NOT NULL,
    nombre_colonia  VARCHAR(100) NOT NULL,
    PRIMARY KEY (id_alcaldia, nombre_colonia),
    FOREIGN KEY (id_alcaldia) REFERENCES alcaldia (id_alcaldia) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 2. INFRAESTRUCTURA
-- ---------------------------------------------------------------------
CREATE TABLE subestacion (
    id_subestacion    INT           PRIMARY KEY,
    nombre            VARCHAR(100)  NOT NULL,
    estado_operativo  VARCHAR(20)   NOT NULL,
    latitud           NUMERIC(9,6)  NOT NULL,
    longitud          NUMERIC(9,6)  NOT NULL,
    CONSTRAINT ck_sub_estado CHECK (estado_operativo IN ('en_operacion','fuera_de_servicio')),
    CONSTRAINT ck_sub_lat    CHECK (latitud  BETWEEN -90  AND 90),
    CONSTRAINT ck_sub_lon    CHECK (longitud BETWEEN -180 AND 180)
);

CREATE TABLE transformador (
    id_transformador            INT           PRIMARY KEY,
    numero_serie_cfe            VARCHAR(30)   NOT NULL UNIQUE,
    capacidad_kva               NUMERIC(8,2)  NOT NULL,
    tipo_instalacion            VARCHAR(20)   NOT NULL,
    latitud                     NUMERIC(9,6)  NOT NULL,
    longitud                    NUMERIC(9,6)  NOT NULL,
    fecha_ultimo_mantenimiento  DATETIME,
    id_subestacion              INT           NOT NULL,
    id_alcaldia                 SMALLINT      NOT NULL,
    nombre_colonia              VARCHAR(100)  NOT NULL,
    FOREIGN KEY (id_subestacion) REFERENCES subestacion (id_subestacion),
    FOREIGN KEY (id_alcaldia, nombre_colonia) REFERENCES colonia (id_alcaldia, nombre_colonia),
    CONSTRAINT ck_tr_cap  CHECK (capacidad_kva > 0),
    CONSTRAINT ck_tr_tipo CHECK (tipo_instalacion IN ('poste','pedestal','subterraneo')),  -- PROPUESTO: CFE define los valores
    CONSTRAINT ck_tr_lat  CHECK (latitud  BETWEEN -90  AND 90),
    CONSTRAINT ck_tr_lon  CHECK (longitud BETWEEN -180 AND 180)
);

CREATE TABLE suministro (
    numero_servicio   CHAR(12)  PRIMARY KEY,
    id_transformador  INT       NOT NULL,
    FOREIGN KEY (id_transformador) REFERENCES transformador (id_transformador),
    CONSTRAINT ck_sum_num CHECK (numero_servicio REGEXP '^[0-9]{12}$')
);

-- Entidad débil por identificación (Regla 8). porcentaje_carga es derivado: ver vista.
CREATE TABLE lectura_carga (
    id_transformador  INT           NOT NULL,
    fecha_hora        DATETIME   NOT NULL,
    carga_kva         NUMERIC(8,2)  NOT NULL,
    PRIMARY KEY (id_transformador, fecha_hora),
    FOREIGN KEY (id_transformador) REFERENCES transformador (id_transformador) ON DELETE CASCADE,
    CONSTRAINT ck_lec_carga CHECK (carga_kva >= 0)
);

-- ---------------------------------------------------------------------
-- 3. ATENCIÓN (se crea antes que orden_trabajo por la FK a cuadrilla)
-- ---------------------------------------------------------------------
CREATE TABLE cuadrilla (
    id_cuadrilla            INT           PRIMARY KEY,
    codigo_cuadrilla        VARCHAR(20)   NOT NULL UNIQUE,
    zona                    VARCHAR(100)  NOT NULL,
    estatus_disponibilidad  VARCHAR(15)   NOT NULL,
    CONSTRAINT ck_cua_estatus CHECK (estatus_disponibilidad IN ('disponible','en_servicio','fuera_de_turno'))  -- PROPUESTO
);

-- Atributo multivaluado (Regla 3)
CREATE TABLE cuadrilla_telefono (
    id_cuadrilla  INT          NOT NULL,
    telefono      VARCHAR(15)  NOT NULL,
    PRIMARY KEY (id_cuadrilla, telefono),
    FOREIGN KEY (id_cuadrilla) REFERENCES cuadrilla (id_cuadrilla) ON DELETE CASCADE,
    CONSTRAINT ck_cuatel CHECK (telefono REGEXP '^[0-9+() -]{7,15}$')
);

CREATE TABLE tecnico (
    id_tecnico    INT           PRIMARY KEY,
    nombre        VARCHAR(100)  NOT NULL,
    rol           VARCHAR(15),
    id_cuadrilla  INT,                         -- NULL: técnico aún sin cuadrilla
    FOREIGN KEY (id_cuadrilla) REFERENCES cuadrilla (id_cuadrilla),   -- sin ON DELETE SET NULL: MySQL no lo permite junto con un CHECK sobre la misma columna
    CONSTRAINT ck_tec_rol CHECK (rol IS NULL OR rol IN ('responsable','integrante')),
    CONSTRAINT ck_tec_rol_cuadrilla CHECK (id_cuadrilla IS NOT NULL OR rol IS NULL)  -- rol nulo si no tiene cuadrilla
    -- RN-02 (mínimo 2 técnicos por cuadrilla) se valida en la aplicación, no con la FK.
);

-- Atributo multivaluado (Regla 3)
CREATE TABLE tecnico_especialidad (
    id_tecnico    INT          NOT NULL,
    especialidad  VARCHAR(60)  NOT NULL,
    PRIMARY KEY (id_tecnico, especialidad),
    FOREIGN KEY (id_tecnico) REFERENCES tecnico (id_tecnico) ON DELETE CASCADE
);

CREATE TABLE supervisor (
    id_supervisor  INT           PRIMARY KEY,
    nombre         VARCHAR(100)  NOT NULL
);

-- ---------------------------------------------------------------------
-- 4. INCIDENTES
-- ---------------------------------------------------------------------
-- Supertipo de la jerarquía (disjunta y total, discriminador origen_reporte)
CREATE TABLE reporte (
    id_reporte           INT           PRIMARY KEY,
    folio_institucional  VARCHAR(30)   NOT NULL UNIQUE,
    origen_reporte       VARCHAR(15)   NOT NULL,
    fecha_hora           DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_falla           VARCHAR(20)   NOT NULL,
    descripcion          TEXT,
    estatus              VARCHAR(15)   NOT NULL DEFAULT 'registrado',
    calle                VARCHAR(100),
    entre_calles         VARCHAR(150),
    codigo_postal        CHAR(5),
    colonia              VARCHAR(100),   -- texto libre, sin FK
    alcaldia             VARCHAR(60),    -- texto libre, sin FK
    entidad              VARCHAR(40),
    referencias          VARCHAR(200),
    id_transformador     INT,            -- NULL hasta conciliar (RC7)
    FOREIGN KEY (id_transformador) REFERENCES transformador (id_transformador),
    CONSTRAINT ck_rep_origen CHECK (origen_reporte IN ('servicio','ubicacion','preventivo')),
    CONSTRAINT ck_rep_falla  CHECK (tipo_falla IN ('sobrecarga','caida_arbol','falla_interna','otro')),
    CONSTRAINT ck_rep_estatus CHECK (estatus IN ('registrado','asignado','en_proceso','cerrado')),
    CONSTRAINT ck_rep_cp CHECK (codigo_postal IS NULL OR codigo_postal REGEXP '^[0-9]{5}$')
);

CREATE TABLE reporte_por_servicio (
    id_reporte         INT          PRIMARY KEY,
    telefono_contacto  VARCHAR(15)  NOT NULL,
    medio_reporte      VARCHAR(20)  NOT NULL,
    numero_servicio    CHAR(12)     NOT NULL,
    FOREIGN KEY (id_reporte)      REFERENCES reporte (id_reporte) ON DELETE CASCADE,
    FOREIGN KEY (numero_servicio) REFERENCES suministro (numero_servicio),
    CONSTRAINT ck_rps_medio CHECK (medio_reporte IN ('telefono','app','web','ventanilla')),  -- PROPUESTO
    CONSTRAINT ck_rps_tel   CHECK (telefono_contacto REGEXP '^[0-9+() -]{7,15}$')
);

CREATE TABLE reporte_por_ubicacion (
    id_reporte          INT           PRIMARY KEY,
    latitud             NUMERIC(9,6)  NOT NULL,
    longitud            NUMERIC(9,6)  NOT NULL,
    radio_afectacion_m  INT           NOT NULL,
    FOREIGN KEY (id_reporte) REFERENCES reporte (id_reporte) ON DELETE CASCADE,
    CONSTRAINT ck_rpu_lat   CHECK (latitud  BETWEEN -90  AND 90),
    CONSTRAINT ck_rpu_lon   CHECK (longitud BETWEEN -180 AND 180),
    CONSTRAINT ck_rpu_radio CHECK (radio_afectacion_m > 0)
);

-- porcentaje_carga: instantánea al momento de generar la alerta (no es atributo derivado)
CREATE TABLE reporte_preventivo (
    id_reporte          INT           PRIMARY KEY,
    porcentaje_carga    NUMERIC(5,2)  NOT NULL,
    umbral_configurado  NUMERIC(5,2)  NOT NULL,
    FOREIGN KEY (id_reporte) REFERENCES reporte (id_reporte) ON DELETE CASCADE,
    CONSTRAINT ck_rpv_pct    CHECK (porcentaje_carga >= 0),
    CONSTRAINT ck_rpv_umbral CHECK (umbral_configurado > 0 AND umbral_configurado <= 100)
);

-- Entidad débil por existencia: PK propia, FK obligatoria al reporte
CREATE TABLE orden_trabajo (
    id_orden             INT          PRIMARY KEY,
    id_reporte           INT          NOT NULL,
    prioridad            VARCHAR(10)  NOT NULL,
    fecha_creacion       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_asignacion     DATETIME,
    fecha_llegada        DATETIME,
    fecha_cierre         DATETIME,
    diagnostico_tecnico  TEXT,
    id_cuadrilla         INT,          -- NULL hasta asignar
    FOREIGN KEY (id_reporte)   REFERENCES reporte (id_reporte),
    FOREIGN KEY (id_cuadrilla) REFERENCES cuadrilla (id_cuadrilla),
    CONSTRAINT ck_ord_prio CHECK (prioridad IN ('alta','media','baja')),
    CONSTRAINT ck_ord_f1 CHECK (fecha_asignacion IS NULL OR fecha_asignacion >= fecha_creacion),
    CONSTRAINT ck_ord_f2 CHECK (fecha_llegada    IS NULL OR (fecha_asignacion IS NOT NULL AND fecha_llegada >= fecha_asignacion)),
    CONSTRAINT ck_ord_f3 CHECK (fecha_cierre     IS NULL OR (fecha_asignacion IS NOT NULL AND fecha_cierre >= fecha_asignacion)),
    CONSTRAINT ck_ord_f4 CHECK (fecha_cierre IS NULL OR fecha_llegada IS NULL OR fecha_cierre >= fecha_llegada),
    CONSTRAINT ck_ord_asig CHECK (fecha_asignacion IS NULL OR id_cuadrilla IS NOT NULL)
);

-- Relación «audita» sobre la agregación Atención (Cuadrilla–Orden)
CREATE TABLE auditoria_atencion (
    id_orden         INT          PRIMARY KEY,
    id_supervisor    INT          NOT NULL,
    fecha_auditoria  DATETIME  NOT NULL,
    cumplio_sla      BOOLEAN      NOT NULL,
    FOREIGN KEY (id_orden)      REFERENCES orden_trabajo (id_orden),
    FOREIGN KEY (id_supervisor) REFERENCES supervisor (id_supervisor)
);

-- ---------------------------------------------------------------------
-- 5. ATRIBUTOS DERIVADOS (no se almacenan: vistas)
-- ---------------------------------------------------------------------
CREATE VIEW v_lectura_carga AS
SELECT l.id_transformador, l.fecha_hora, l.carga_kva, t.capacidad_kva,
       ROUND(l.carga_kva / t.capacidad_kva * 100, 2) AS porcentaje_carga
FROM lectura_carga l
JOIN transformador t USING (id_transformador);

CREATE VIEW v_orden_tiempos AS
SELECT id_orden, id_reporte, id_cuadrilla,
       TIMESTAMPDIFF(MINUTE, fecha_asignacion, fecha_llegada) AS tiempo_respuesta_min,
       TIMESTAMPDIFF(MINUTE, fecha_asignacion, fecha_cierre)  AS tiempo_resolucion_min
FROM orden_trabajo;

-- ---------------------------------------------------------------------
-- 6. JERARQUÍA DE REPORTE (disjunta) · Regla 9, estrategia A
--    El subtipo insertado debe coincidir con origen_reporte.
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_rps_ins BEFORE INSERT ON reporte_por_servicio
FOR EACH ROW
BEGIN
    IF NOT ((SELECT origen_reporte FROM reporte WHERE id_reporte = NEW.id_reporte) <=> 'servicio') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El reporte no tiene origen_reporte = servicio';
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_rps_upd BEFORE UPDATE ON reporte_por_servicio
FOR EACH ROW
BEGIN
    IF NOT ((SELECT origen_reporte FROM reporte WHERE id_reporte = NEW.id_reporte) <=> 'servicio') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El reporte no tiene origen_reporte = servicio';
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_rpu_ins BEFORE INSERT ON reporte_por_ubicacion
FOR EACH ROW
BEGIN
    IF NOT ((SELECT origen_reporte FROM reporte WHERE id_reporte = NEW.id_reporte) <=> 'ubicacion') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El reporte no tiene origen_reporte = ubicacion';
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_rpu_upd BEFORE UPDATE ON reporte_por_ubicacion
FOR EACH ROW
BEGIN
    IF NOT ((SELECT origen_reporte FROM reporte WHERE id_reporte = NEW.id_reporte) <=> 'ubicacion') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El reporte no tiene origen_reporte = ubicacion';
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_rpv_ins BEFORE INSERT ON reporte_preventivo
FOR EACH ROW
BEGIN
    IF NOT ((SELECT origen_reporte FROM reporte WHERE id_reporte = NEW.id_reporte) <=> 'preventivo') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El reporte no tiene origen_reporte = preventivo';
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_rpv_upd BEFORE UPDATE ON reporte_preventivo
FOR EACH ROW
BEGIN
    IF NOT ((SELECT origen_reporte FROM reporte WHERE id_reporte = NEW.id_reporte) <=> 'preventivo') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El reporte no tiene origen_reporte = preventivo';
    END IF;
END$$
DELIMITER ;

-- =====================================================================
-- DATOS DE PRUEBA (válidos)
-- =====================================================================
INSERT INTO alcaldia VALUES (1,'Gustavo A. Madero'),(2,'Iztapalapa');
INSERT INTO colonia VALUES (1,'Lindavista'),(1,'Zacatenco'),(2,'Santa Martha Acatitla');
INSERT INTO subestacion VALUES (1,'SE Magdalena de las Salinas','en_operacion',19.4950,-99.1180),
                               (2,'SE Iztapalapa Norte','en_operacion',19.3600,-99.0500);
INSERT INTO transformador VALUES
 (1,'TR-GAM-0001',75.00,'poste',19.4900,-99.1300, NOW() - INTERVAL 400 DAY,1,1,'Lindavista'),
 (2,'TR-GAM-0002',112.50,'poste',19.5020,-99.1370, NOW() - INTERVAL 30 DAY,1,1,'Zacatenco'),
 (3,'TR-IZT-0001',150.00,'pedestal',19.3550,-99.0400, NULL,2,2,'Santa Martha Acatitla');
INSERT INTO suministro VALUES ('010000000001',1),('010000000002',1),('010000000003',2),('020000000001',3);
INSERT INTO lectura_carga VALUES
 (1, NOW() - INTERVAL 9 HOUR, 60.00),
 (1, NOW() - INTERVAL 6 HOUR, 68.00),
 (1, NOW() - INTERVAL 3 HOUR, 74.00),
 (2, NOW() - INTERVAL 3 HOUR, 50.00),
 (3, NOW() - INTERVAL 3 HOUR, 90.00);

START TRANSACTION;
INSERT INTO cuadrilla VALUES (1,'CUA-GAM-01','Gustavo A. Madero','disponible'),(2,'CUA-IZT-01','Iztapalapa','disponible');
INSERT INTO cuadrilla_telefono VALUES (1,'5555550101'),(1,'5555550102'),(2,'5555550201');
COMMIT;
INSERT INTO tecnico VALUES (1,'Luis Ramírez','responsable',1),(2,'Marta Soto','integrante',1),(3,'Iván Cruz','responsable',2),(4,'Rosa Peña','integrante',2);
INSERT INTO tecnico_especialidad VALUES (1,'media tensión'),(1,'transformadores'),(2,'redes subterráneas'),(3,'transformadores');
INSERT INTO supervisor VALUES (1,'Gabriela Núñez');

-- Cada reporte con su subtipo en la misma transacción
START TRANSACTION;
INSERT INTO reporte (id_reporte,folio_institucional,origen_reporte,tipo_falla,descripcion,calle,codigo_postal,colonia,alcaldia,entidad,id_transformador)
 VALUES (1,'REP-2026-0001','servicio','falla_interna','Sin luz desde las 18:00','Av. Instituto Politécnico Nacional','07300','Lindavista','Gustavo A. Madero','CDMX',1);
INSERT INTO reporte_por_servicio VALUES (1,'5555559999','telefono','010000000001');

INSERT INTO reporte (id_reporte,folio_institucional,origen_reporte,tipo_falla,descripcion,id_transformador)
 VALUES (2,'REP-2026-0002','ubicacion','caida_arbol','Árbol sobre la línea, sin luz en la cuadra',NULL);
INSERT INTO reporte_por_ubicacion VALUES (2,19.5025,-99.1365,300);

INSERT INTO reporte (id_reporte,folio_institucional,origen_reporte,tipo_falla,descripcion,id_transformador)
 VALUES (3,'REP-2026-0003','preventivo','sobrecarga','Carga del transformador sobre el umbral',3);
INSERT INTO reporte_preventivo VALUES (3,60.00,50.00);
COMMIT;

INSERT INTO orden_trabajo (id_orden,id_reporte,prioridad,fecha_creacion,fecha_asignacion,fecha_llegada,fecha_cierre,diagnostico_tecnico,id_cuadrilla)
 VALUES (1,1,'alta', NOW() - INTERVAL 5 HOUR, NOW() - INTERVAL 4 HOUR, NOW() - INTERVAL 3 HOUR, NOW() - INTERVAL 2 HOUR,'Fusible dañado',1),
        (2,3,'media',NOW() - INTERVAL 1 HOUR,  NULL,NULL,NULL,NULL,NULL);
INSERT INTO auditoria_atencion VALUES (1,1,NOW() - INTERVAL 1 HOUR,true);