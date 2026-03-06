-- =====================================================
-- ARCHIVO: 3 Reportes adicionales
-- Contiene:
-- 1. Reporte de contratos por vencer (próximos 30 días)
-- 2. Reporte semanal de pagos recibidos
-- 3. Reporte de propiedades por ciudad con estadísticas
-- =====================================================

USE db_proyecto;

-- =====================================================
-- REPORTE 1: Contratos que vencen en los próximos 30 días
-- =====================================================
-- Tabla donde se guarda el reporte
CREATE TABLE IF NOT EXISTS reporte_contratos_por_vencer (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    id_contrato INT NOT NULL,
    nombre_cliente VARCHAR(90),
    nombre_agente VARCHAR(90),
    direccion_propiedad VARCHAR(100),
    tipo_contrato VARCHAR(20),
    fecha_fin DATETIME,
    dias_restantes INT,
    deuda_pendiente DECIMAL(12,2),
    generado_el DATETIME DEFAULT NOW()
);

DELIMITER //

-- Evento que se ejecuta TODOS LOS DÍAS a medianoche
CREATE EVENT reporte_por_vencer_diario
ON SCHEDULE
    EVERY 1 DAY
    STARTS CURRENT_DATE + INTERVAL 1 DAY  -- Empieza mañana a las 00:00
DO
BEGIN
    -- Insertar en el reporte todos los contratos que vencen en 30 días o menos
    INSERT INTO reporte_contratos_por_vencer (
        id_contrato, nombre_cliente, nombre_agente,
        direccion_propiedad, tipo_contrato, fecha_fin,
        dias_restantes, deuda_pendiente
    )
    SELECT
        -- Datos del contrato
        c.id_contrato,
        -- Nombre del cliente
        CONCAT(pc.nombre, ' ', pc.apellido),
        -- Nombre del agente
        CONCAT(pa.nombre, ' ', pa.apellido),
        -- Dirección de la propiedad
        pr.direccion,
        -- Tipo de contrato (venta/arriendo)
        tc.nombre,
        -- Fecha en que vence
        c.fecha_fin,
        -- Cuántos días faltan
        DATEDIFF(c.fecha_fin, CURRENT_DATE),
        -- Deuda pendiente (total - pagado)
        c.total - COALESCE(pagos.total_pagado, 0)
    FROM contrato c
    INNER JOIN personas pc ON c.cliente_id = pc.id_persona
    INNER JOIN personas pa ON c.agente_id = pa.id_persona
    INNER JOIN propiedad pr ON c.propiedad_id = pr.id_propiedad
    INNER JOIN tipo_contrato tc ON c.tipo_contrato_id = tc.id_tipo_contrato
    LEFT JOIN (
        SELECT f.contrato_id, SUM(pa.monto) AS total_pagado
        FROM pago pa
        INNER JOIN factura f ON pa.factura_id = f.id_factura
        WHERE pa.monto > 0
        GROUP BY f.contrato_id
    ) pagos ON c.id_contrato = pagos.contrato_id
    -- FILTRO: solo contratos que vencen en 30 días o menos y aún no vencieron
    WHERE DATEDIFF(c.fecha_fin, CURRENT_DATE) BETWEEN 0 AND 30;
END //

DELIMITER ;


-- =====================================================
-- REPORTE 2: Resumen semanal de pagos recibidos
-- =====================================================
-- Tabla donde se guarda el reporte
CREATE TABLE IF NOT EXISTS reporte_pagos_semanal (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    semana VARCHAR(20) NOT NULL,           -- Ej: "2025-S23" (año-semana)
    cantidad_pagos INT,
    total_recaudado DECIMAL(12,2),
    pago_promedio DECIMAL(12,2),
    pago_maximo DECIMAL(12,2),
    pago_minimo DECIMAL(12,2),
    generado_el DATETIME DEFAULT NOW()
);

DELIMITER //

-- Evento que se ejecuta cada LUNES a medianoche
CREATE EVENT reporte_pagos_semanal_evento
ON SCHEDULE
    EVERY 1 WEEK
    -- Calcular el próximo lunes como inicio
    STARTS CURRENT_DATE + INTERVAL (7 - WEEKDAY(CURRENT_DATE)) DAY
DO
BEGIN
    -- Variables para guardar los cálculos
    DECLARE v_cantidad INT DEFAULT 0;
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    DECLARE v_promedio DECIMAL(12,2) DEFAULT 0;
    DECLARE v_maximo DECIMAL(12,2) DEFAULT 0;
    DECLARE v_minimo DECIMAL(12,2) DEFAULT 0;
    DECLARE v_semana VARCHAR(20);

    -- Calcular el identificador de la semana (ej: "2025-S23")
    SET v_semana = CONCAT(YEAR(NOW()), '-S', LPAD(WEEK(NOW()), 2, '0'));

    -- Calcular estadísticas de los pagos de la última semana
    SELECT
        COUNT(*),
        COALESCE(SUM(monto), 0),
        COALESCE(AVG(monto), 0),
        COALESCE(MAX(monto), 0),
        COALESCE(MIN(monto), 0)
    INTO v_cantidad, v_total, v_promedio, v_maximo, v_minimo
    FROM pago
    WHERE monto > 0
    AND fecha_pago >= DATE_SUB(NOW(), INTERVAL 7 DAY);

    -- Solo insertar si hubo pagos en la semana
    IF v_cantidad > 0 THEN
        INSERT INTO reporte_pagos_semanal (
            semana, cantidad_pagos, total_recaudado,
            pago_promedio, pago_maximo, pago_minimo
        )
        VALUES (
            v_semana, v_cantidad, v_total,
            v_promedio, v_maximo, v_minimo
        );
    END IF;
END //

DELIMITER ;


-- =====================================================
-- REPORTE 3: Estadísticas de propiedades por ciudad
-- =====================================================
-- Tabla donde se guarda el reporte
CREATE TABLE IF NOT EXISTS reporte_propiedades_ciudad (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    periodo VARCHAR(7) NOT NULL,           -- "2025-06"
    ciudad VARCHAR(45),
    total_propiedades INT,
    disponibles INT,
    arrendadas INT,
    vendidas INT,
    precio_promedio DECIMAL(12,2),
    precio_total DECIMAL(12,2),
    generado_el DATETIME DEFAULT NOW()
);

DELIMITER //

-- Evento que se ejecuta el primer día de cada mes
CREATE EVENT reporte_propiedades_ciudad_mensual
ON SCHEDULE
    EVERY 1 MONTH
    STARTS LAST_DAY(CURRENT_DATE) + INTERVAL 1 DAY
DO
BEGIN
    -- Insertar estadísticas agrupadas por ciudad
    INSERT INTO reporte_propiedades_ciudad (
        periodo, ciudad, total_propiedades,
        disponibles, arrendadas, vendidas,
        precio_promedio, precio_total
    )
    SELECT
        -- Período actual
        DATE_FORMAT(NOW(), '%Y-%m'),
        -- Nombre de la ciudad
        c.nombre,
        -- Total de propiedades en esa ciudad
        COUNT(*),
        -- Cuántas están disponibles (estado 1)
        SUM(CASE WHEN p.id_estado_propiedad = 1 THEN 1 ELSE 0 END),
        -- Cuántas están arrendadas (estado 2)
        SUM(CASE WHEN p.id_estado_propiedad = 2 THEN 1 ELSE 0 END),
        -- Cuántas están vendidas (estado 3)
        SUM(CASE WHEN p.id_estado_propiedad = 3 THEN 1 ELSE 0 END),
        -- Precio promedio en esa ciudad
        AVG(p.precio),
        -- Valor total de propiedades en esa ciudad
        SUM(p.precio)
    FROM propiedad p
    INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
    GROUP BY c.nombre;
END //

DELIMITER ;

-- =====================================================
-- PRUEBAS MANUALES (ejecutar los reportes ahora sin esperar)
-- =====================================================

-- Reporte 1: Contratos por vencer
-- (puede que no haya resultados si ningún contrato vence en 30 días)
-- Para probar, podés cambiar el BETWEEN 0 AND 30 por BETWEEN 0 AND 365

-- INSERT INTO reporte_contratos_por_vencer (
--     id_contrato, nombre_cliente, nombre_agente,
--     direccion_propiedad, tipo_contrato, fecha_fin,
--     dias_restantes, deuda_pendiente
-- )
-- SELECT c.id_contrato, CONCAT(pc.nombre, ' ', pc.apellido),
--     CONCAT(pa.nombre, ' ', pa.apellido), pr.direccion, tc.nombre,
--     c.fecha_fin, DATEDIFF(c.fecha_fin, CURRENT_DATE),
--     c.total - COALESCE(pagos.total_pagado, 0)
-- FROM contrato c
-- INNER JOIN personas pc ON c.cliente_id = pc.id_persona
-- INNER JOIN personas pa ON c.agente_id = pa.id_persona
-- INNER JOIN propiedad pr ON c.propiedad_id = pr.id_propiedad
-- INNER JOIN tipo_contrato tc ON c.tipo_contrato_id = tc.id_tipo_contrato
-- LEFT JOIN (
--     SELECT f.contrato_id, SUM(pa.monto) AS total_pagado
--     FROM pago pa INNER JOIN factura f ON pa.factura_id = f.id_factura
--     WHERE pa.monto > 0 GROUP BY f.contrato_id
-- ) pagos ON c.id_contrato = pagos.contrato_id
-- WHERE DATEDIFF(c.fecha_fin, CURRENT_DATE) BETWEEN 0 AND 365;
-- SELECT * FROM reporte_contratos_por_vencer;

-- Reporte 3: Propiedades por ciudad (ejecutar manualmente)
-- INSERT INTO reporte_propiedades_ciudad (
--     periodo, ciudad, total_propiedades, disponibles, arrendadas, vendidas,
--     precio_promedio, precio_total
-- )
-- SELECT DATE_FORMAT(NOW(), '%Y-%m'), c.nombre, COUNT(*),
--     SUM(CASE WHEN p.id_estado_propiedad = 1 THEN 1 ELSE 0 END),
--     SUM(CASE WHEN p.id_estado_propiedad = 2 THEN 1 ELSE 0 END),
--     SUM(CASE WHEN p.id_estado_propiedad = 3 THEN 1 ELSE 0 END),
--     AVG(p.precio), SUM(p.precio)
-- FROM propiedad p INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
-- GROUP BY c.nombre;
-- SELECT * FROM reporte_propiedades_ciudad;