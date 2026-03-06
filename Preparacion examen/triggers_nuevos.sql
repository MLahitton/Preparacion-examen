-- =====================================================
-- ARCHIVO: Nuevos triggers para el sistema
-- Contiene 3 triggers:
-- 1. auto_estado_propiedad_contrato → Al crear contrato, cambia estado de la propiedad
-- 2. validar_pago_factura → Al pagar, actualiza estado factura si deuda = 0
-- 3. impedir_borrar_contrato → Impide borrar contrato si tiene pagos
-- =====================================================

USE db_proyecto;

DELIMITER //

-- =====================================================
-- TRIGGER 1: auto_estado_propiedad_contrato
-- ¿Cuándo se activa? DESPUÉS de insertar un contrato nuevo
-- ¿Qué hace? Cambia automáticamente el estado de la propiedad:
--   Si el contrato es de VENTA (tipo 1) → estado "vendida" (3)
--   Si el contrato es de ARRIENDO (tipo 2) → estado "arrendada" (2)
-- =====================================================
CREATE TRIGGER auto_estado_propiedad_contrato
AFTER INSERT ON contrato
FOR EACH ROW
BEGIN
    -- Variable para guardar el nuevo estado
    DECLARE v_nuevo_estado INT;

    -- Determinar el nuevo estado según el tipo de contrato
    IF NEW.tipo_contrato_id = 1 THEN
        -- Contrato de VENTA → la propiedad pasa a "vendida" (id 3)
        SET v_nuevo_estado = 3;
    ELSE
        -- Contrato de ARRIENDO → la propiedad pasa a "arrendada" (id 2)
        SET v_nuevo_estado = 2;
    END IF;

    -- Actualizar el estado de la propiedad automáticamente
    UPDATE propiedad
    SET id_estado_propiedad = v_nuevo_estado
    WHERE id_propiedad = NEW.propiedad_id;

    -- Nota: este UPDATE va a activar también el trigger "vigilar_propiedad"
    -- que ya tenías, así que el cambio de estado quedará registrado en logs
END //


-- =====================================================
-- TRIGGER 2: validar_pago_factura
-- ¿Cuándo se activa? DESPUÉS de insertar un pago
-- ¿Qué hace? Revisa si con este pago ya se cubrió toda la deuda
--   del contrato. Si la deuda llega a 0 → cambia el estado
--   de la factura a "pagado" (id 1)
-- =====================================================
CREATE TRIGGER validar_pago_factura
AFTER INSERT ON pago
FOR EACH ROW
BEGIN
    -- Variables auxiliares
    DECLARE v_contrato_id INT;
    DECLARE v_total_contrato DECIMAL(12,2);
    DECLARE v_total_pagado DECIMAL(12,2);

    -- Solo procesar si el monto es mayor a 0
    -- (los pagos en $0 son placeholders y no cuentan)
    IF NEW.monto > 0 THEN

        -- Obtener el contrato asociado a esta factura
        SELECT contrato_id INTO v_contrato_id
        FROM factura
        WHERE id_factura = NEW.factura_id;

        -- Obtener el total del contrato
        SELECT total INTO v_total_contrato
        FROM contrato
        WHERE id_contrato = v_contrato_id;

        -- Sumar TODOS los pagos hechos a esta factura
        SELECT COALESCE(SUM(monto), 0) INTO v_total_pagado
        FROM pago
        WHERE factura_id = NEW.factura_id
        AND monto > 0;

        -- Si lo pagado cubre el total → marcar factura como "pagado"
        IF v_total_pagado >= v_total_contrato THEN
            UPDATE factura
            SET estado_factura_id = 1  -- 1 = pagado
            WHERE id_factura = NEW.factura_id;
        END IF;

        -- Registrar el pago en los logs
        CALL escribir_log(
            'pago',
            'validar_pago_factura',
            'INSERT',
            CONCAT(
                'Pago de $', FORMAT(NEW.monto, 0),
                ' en factura #', NEW.factura_id,
                ' | Total pagado: $', FORMAT(v_total_pagado, 0),
                ' de $', FORMAT(v_total_contrato, 0)
            )
        );
    END IF;
END //


-- =====================================================
-- TRIGGER 3: impedir_borrar_contrato
-- ¿Cuándo se activa? ANTES de borrar un contrato
-- ¿Qué hace? Verifica si el contrato tiene facturas con pagos.
--   Si los tiene → IMPIDE el borrado lanzando un error.
--   Esto protege la integridad de los datos financieros.
-- =====================================================
CREATE TRIGGER impedir_borrar_contrato
BEFORE DELETE ON contrato
FOR EACH ROW
BEGIN
    DECLARE v_pagos INT DEFAULT 0;

    -- Contar cuántos pagos existen asociados a este contrato
    -- Recorrido: contrato → factura → pago
    SELECT COUNT(*) INTO v_pagos
    FROM pago p
    INNER JOIN factura f ON p.factura_id = f.id_factura
    WHERE f.contrato_id = OLD.id_contrato
    AND p.monto > 0;

    -- Si tiene pagos con monto mayor a 0 → no se puede borrar
    IF v_pagos > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar un contrato que tiene pagos registrados';
    END IF;

    -- Si llega aquí es porque no tiene pagos → registrar en logs que se borró
    CALL escribir_log(
        'contrato',
        'impedir_borrar_contrato',
        'DELETE',
        CONCAT('Se eliminó el contrato #', OLD.id_contrato,
               ' | Total: $', FORMAT(OLD.total, 0))
    );
END //

DELIMITER ;

-- =====================================================
-- PRUEBAS
-- =====================================================

-- Trigger 1: Insertar un contrato y ver que la propiedad cambia de estado
-- INSERT INTO contrato (tipo_contrato_id, propiedad_id, fecha_inicio, fecha_fin, total, cliente_id, agente_id)
-- VALUES (1, 4, '2025-10-01', '2026-10-01', 260000000.00, 1, 2);
-- SELECT * FROM propiedad WHERE id_propiedad = 4;  -- debería decir "vendida"
-- SELECT * FROM logs ORDER BY id_logs DESC;

-- Trigger 2: Insertar un pago que cubra la deuda
-- INSERT INTO pago (factura_id, tipo_pago_id, monto, fecha_pago)
-- VALUES (1, 2, 420000000.00, NOW());
-- SELECT * FROM factura WHERE id_factura = 1;  -- estado debería ser 1 (pagado)
-- SELECT * FROM logs ORDER BY id_logs DESC;

-- Trigger 3: Intentar borrar contrato con pagos → debería fallar
-- DELETE FROM contrato WHERE id_contrato = 2;
-- Deberías ver: "No se puede eliminar un contrato que tiene pagos registrados"