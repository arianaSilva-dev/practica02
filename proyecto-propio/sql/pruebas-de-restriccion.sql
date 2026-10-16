use cfe;

-- =====================================================================
-- INSERTs QUE DEBEN SER RECHAZADOS (Ej. 6.2)
-- =====================================================================

-- R1 · CHECK: capacidad_kva > 0
INSERT INTO transformador VALUES (90,'TR-X-0090',-10,'poste',19.49,-99.13,NULL,1,1,'Lindavista');
-- ERROR: viola ck_tr_cap

-- R2 · UNIQUE: numero_serie_cfe repetido
INSERT INTO transformador VALUES (91,'TR-GAM-0001',75,'poste',19.49,-99.13,NULL,1,1,'Lindavista');
-- ERROR: viola transformador_numero_serie_cfe_key

-- R3 · FK compuesta: la colonia no existe
INSERT INTO transformador VALUES (92,'TR-X-0092',75,'poste',19.49,-99.13,NULL,1,1,'Colonia Inexistente');
-- ERROR: viola la FK (id_alcaldia, nombre_colonia) → colonia

-- R4 · NOT NULL: suministro sin transformador
INSERT INTO suministro (numero_servicio) VALUES ('030000000001');
-- ERROR: id_transformador es NOT NULL

-- R5 · CHECK de lista: estatus fuera del catálogo
INSERT INTO reporte (id_reporte,folio_institucional,origen_reporte,tipo_falla,estatus)
 VALUES (93,'REP-2026-0093','servicio','otro','inventado');
-- ERROR: viola ck_rep_estatus

-- R6 · Jerarquía disjunta: subtipo que no coincide con origen_reporte
START TRANSACTION;
INSERT INTO reporte (id_reporte,folio_institucional,origen_reporte,tipo_falla)
 VALUES (95,'REP-2026-0095','servicio','otro');
INSERT INTO reporte_preventivo VALUES (95,60,50);
-- ERROR: El reporte no tiene origen_reporte = preventivo
ROLLBACK;

-- R7 · Orden sin reporte (FK obligatoria, dependencia por existencia)
INSERT INTO orden_trabajo (id_orden,id_reporte,prioridad) VALUES (93,9999,'alta');
-- ERROR: viola la FK orden_trabajo_id_reporte_fkey

-- R8 · Fechas incoherentes: cierre antes de la llegada
INSERT INTO orden_trabajo (id_orden,id_reporte,prioridad,fecha_creacion,fecha_asignacion,fecha_llegada,fecha_cierre,id_cuadrilla)
 VALUES (94,2,'baja', NOW(), NOW(), NOW(), NOW() - INTERVAL 1 DAY, 1);
-- ERROR: viola ck_ord_f3 (o ck_ord_f4)

-- R9 · Técnico con rol pero sin cuadrilla (el rol es nulo si no tiene cuadrilla)
INSERT INTO tecnico VALUES (99,'Persona Prueba','integrante',NULL);
-- ERROR: viola ck_tec_rol_cuadrilla