-- =====================================================
-- ARCHIVO: Nuevas funciones para el sistema
-- Contiene 4 funciones adicionales:
-- 1. calcular_iva → calcula el IVA (19%) de un contrato
-- 2. dias_restantes_contrato → días que faltan para que venza
-- 3. obtener_estado_contrato → si está Vigente, Vencido o Por vencer
-- 4. total_pagos_cliente → cuánto ha pagado un cliente en total
-- =====================================================

USE db_proyecto;

DELIMITER //

-- =====================================================
-- FUNCIÓN 1: calcular_iva
-- Recibe: el ID de un contrato
-- Devuelve: el valor del IVA (19%) sobre el total del contrato
-- Ejemplo: contrato de $100M → devuelve $19M
-- =====================================================
CREATE FUNCTION calcular_iva(p_id_contrato INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    -- Variable para guardar el total del contrato
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    -- Variable para verificar que el contrato exista
    DECLARE existe INT DEFAULT 0;

    -- Verificar que el contrato existe
    SELECT COUNT(*) INTO existe
    FROM contrato
    WHERE id_contrato = p_id_contrato;

    -- Si no existe, lanzar error
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El contrato no existe para calcular IVA';
    END IF;

    -- Obtener el total del contrato
    SELECT total INTO v_total
    FROM contrato
    WHERE id_contrato = p_id_contrato;

    -- Devolver el 19% del total (IVA en Colombia)
    RETURN ROUND(v_total * 0.19, 2);
END //


-- =====================================================
-- FUNCIÓN 2: dias_restantes_contrato
-- Recibe: el ID de un contrato
-- Devuelve: cuántos días faltan para que termine
--           Si ya venció, devuelve número negativo
-- Ejemplo: vence en 30 días → devuelve 30
--          venció hace 5 días → devuelve -5
-- =====================================================
CREATE FUNCTION dias_restantes_contrato(p_id_contrato INT)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE v_fecha_fin DATETIME;
    DECLARE existe INT DEFAULT 0;

    -- Verificar que el contrato existe
    SELECT COUNT(*) INTO existe
    FROM contrato
    WHERE id_contrato = p_id_contrato;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El contrato no existe';
    END IF;

    -- Obtener la fecha de fin del contrato
    SELECT fecha_fin INTO v_fecha_fin
    FROM contrato
    WHERE id_contrato = p_id_contrato;

    -- DATEDIFF calcula: fecha_fin - hoy = días restantes
    -- Positivo = faltan días, Negativo = ya venció
    RETURN DATEDIFF(v_fecha_fin, CURRENT_DATE);
END //


-- =====================================================
-- FUNCIÓN 3: obtener_estado_contrato
-- Recibe: el ID de un contrato
-- Devuelve: texto con el estado:
--   'Vigente'     → aún no vence
--   'Por vencer'  → vence en menos de 30 días
--   'Vencido'     → ya pasó la fecha de fin
-- =====================================================
CREATE FUNCTION obtener_estado_contrato(p_id_contrato INT)
RETURNS VARCHAR(20)
DETERMINISTIC
BEGIN
    DECLARE v_dias INT DEFAULT 0;
    DECLARE existe INT DEFAULT 0;

    -- Verificar que el contrato existe
    SELECT COUNT(*) INTO existe
    FROM contrato
    WHERE id_contrato = p_id_contrato;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El contrato no existe';
    END IF;

    -- Usamos la función que acabamos de crear para obtener los días
    SET v_dias = dias_restantes_contrato(p_id_contrato);

    -- Clasificar según los días restantes
    IF v_dias < 0 THEN
        RETURN 'Vencido';          -- Ya pasó la fecha de fin
    ELSEIF v_dias <= 30 THEN
        RETURN 'Por vencer';       -- Le quedan 30 días o menos
    ELSE
        RETURN 'Vigente';          -- Todavía tiene tiempo
    END IF;
END //


-- =====================================================
-- FUNCIÓN 4: total_pagos_cliente
-- Recibe: el ID de un cliente
-- Devuelve: la suma total de TODOS los pagos que ha hecho
--           en TODOS sus contratos
-- =====================================================
CREATE FUNCTION total_pagos_cliente(p_id_cliente INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    DECLARE existe INT DEFAULT 0;

    -- Verificar que el cliente existe
    SELECT COUNT(*) INTO existe
    FROM cliente
    WHERE id_cliente = p_id_cliente;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El cliente no existe';
    END IF;

    -- Sumar todos los pagos del cliente
    -- Recorrido: cliente → contrato → factura → pago
    SELECT COALESCE(SUM(pa.monto), 0) INTO v_total
    FROM pago pa
    INNER JOIN factura f ON pa.factura_id = f.id_factura
    INNER JOIN contrato c ON f.contrato_id = c.id_contrato
    WHERE c.cliente_id = p_id_cliente
    AND pa.monto > 0;

    RETURN v_total;
END //

DELIMITER ;

-- =====================================================
-- PRUEBAS
-- =====================================================

-- Probar calcular_iva
-- Contrato 1 ($420M) → IVA = $79,800,000
-- SELECT calcular_iva(1);
-- SELECT calcular_iva(2);

-- Probar dias_restantes_contrato
-- SELECT dias_restantes_contrato(1);
-- SELECT dias_restantes_contrato(2);

-- Probar obtener_estado_contrato
-- SELECT obtener_estado_contrato(1);
-- SELECT obtener_estado_contrato(2);

-- Probar total_pagos_cliente
-- Cliente 2 (Ximena) pagó $180M → debería dar 180000000
-- Cliente 1 (Manuel) pagó $0 → debería dar 0
-- SELECT total_pagos_cliente(1);
-- SELECT total_pagos_cliente(2);

-- Ver todo junto
-- SELECT
--     c.id_contrato,
--     FORMAT(c.total, 0) AS total,
--     FORMAT(calcular_iva(c.id_contrato), 0) AS iva,
--     dias_restantes_contrato(c.id_contrato) AS dias_restantes,
--     obtener_estado_contrato(c.id_contrato) AS estado
-- FROM contrato c;