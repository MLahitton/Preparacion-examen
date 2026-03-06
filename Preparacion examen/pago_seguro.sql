-- =====================================================
-- PROCEDIMIENTO: registrar_pago_seguro
-- ¿Qué hace? Inserta un pago validando que la factura exista,
-- que el monto sea válido, y que no se pague más de lo que se debe.
-- Si todo sale bien, actualiza el estado de la factura a "pagado"
-- cuando la deuda llega a 0
-- =====================================================

USE db_proyecto;

DELIMITER //

CREATE PROCEDURE registrar_pago_seguro(
    IN p_factura_id INT,        -- ID de la factura a la que se le paga
    IN p_tipo_pago INT,         -- 1=efectivo, 2=transferencia, 3=tarjeta, 4=consignación
    IN p_monto DECIMAL(12,2)    -- Cuánto se paga
)
BEGIN
    -- Variables para capturar errores
    DECLARE error_sql CHAR(5);
    DECLARE codigo_sql INT;
    DECLARE mensaje_sql TEXT;
    -- Variables auxiliares
    DECLARE existe INT DEFAULT 0;
    DECLARE v_contrato_id INT;
    DECLARE v_total_contrato DECIMAL(12,2) DEFAULT 0;
    DECLARE v_ya_pagado DECIMAL(12,2) DEFAULT 0;
    DECLARE v_deuda_actual DECIMAL(12,2) DEFAULT 0;

    -- =====================================================
    -- MANEJADOR DE ERRORES
    -- =====================================================
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            error_sql = RETURNED_SQLSTATE,
            codigo_sql = MYSQL_ERRNO,
            mensaje_sql = MESSAGE_TEXT;

        INSERT INTO logs_error (
            tabla_afectada, procedimiento, tipo_objeto,
            codigo_error, mensaje, fecha_registro
        )
        VALUES (
            'pago',
            'registrar_pago_seguro',
            'PROCEDURE',
            codigo_sql,
            mensaje_sql,
            NOW()
        );

        RESIGNAL;
    END;

    -- =====================================================
    -- VALIDACIÓN 1: El monto debe ser mayor a 0
    -- =====================================================
    IF p_monto <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El monto del pago debe ser mayor a cero';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 2: La factura debe existir
    -- =====================================================
    SELECT COUNT(*) INTO existe
    FROM factura
    WHERE id_factura = p_factura_id;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La factura indicada no existe';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 3: El tipo de pago debe existir
    -- =====================================================
    SET existe = 0;
    SELECT COUNT(*) INTO existe
    FROM tipo_pago
    WHERE id_tipo_pago = p_tipo_pago;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El tipo de pago no existe';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 4: No pagar más de lo que se debe
    -- =====================================================
    -- Obtener el contrato asociado a la factura
    SELECT contrato_id INTO v_contrato_id
    FROM factura
    WHERE id_factura = p_factura_id;

    -- Obtener el total del contrato
    SELECT total INTO v_total_contrato
    FROM contrato
    WHERE id_contrato = v_contrato_id;

    -- Obtener cuánto se ha pagado ya
    SELECT COALESCE(SUM(monto), 0) INTO v_ya_pagado
    FROM pago
    WHERE factura_id = p_factura_id
    AND monto > 0;

    -- Calcular la deuda actual
    SET v_deuda_actual = v_total_contrato - v_ya_pagado;

    -- Si el monto que quieren pagar es mayor a la deuda → error
    IF p_monto > v_deuda_actual THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El monto del pago supera la deuda pendiente del contrato';
    END IF;

    -- =====================================================
    -- Todo validado → insertar el pago
    -- =====================================================
    INSERT INTO pago (factura_id, tipo_pago_id, monto, fecha_pago)
    VALUES (p_factura_id, p_tipo_pago, p_monto, NOW());

    -- =====================================================
    -- Si con este pago la deuda llega a 0 → actualizar
    -- el estado de la factura a "pagado" (id = 1)
    -- =====================================================
    IF (v_deuda_actual - p_monto) <= 0 THEN
        UPDATE factura
        SET estado_factura_id = 1  -- 1 = pagado
        WHERE id_factura = p_factura_id;
    END IF;

    -- Registrar en logs que se hizo un pago
    CALL escribir_log(
        'pago',
        'registrar_pago_seguro',
        'INSERT',
        CONCAT(
            'Pago registrado por $', FORMAT(p_monto, 0),
            ' en factura #', p_factura_id,
            ' | Contrato #', v_contrato_id,
            ' | Deuda restante: $', FORMAT(v_deuda_actual - p_monto, 0)
        )
    );

END //

DELIMITER ;

-- =====================================================
-- PRUEBAS
-- =====================================================

-- ✅ Pago exitoso en factura 1 (tiene deuda de $420M)
-- CALL registrar_pago_seguro(1, 2, 100000000.00);
-- SELECT * FROM pago ORDER BY id_pago DESC;
-- SELECT * FROM logs ORDER BY id_logs DESC;

-- ❌ Monto negativo
-- CALL registrar_pago_seguro(1, 1, -5000.00);

-- ❌ Factura inexistente
-- CALL registrar_pago_seguro(999, 1, 50000.00);

-- ❌ Pagar más de lo que se debe
-- CALL registrar_pago_seguro(1, 1, 999999999999.00);

-- Ver errores:
-- SELECT * FROM logs_error ORDER BY id_logs_error DESC;