-- =====================================================
-- ARCHIVO: Procedimiento con Transacciones
-- ¿Qué hace? Crea un contrato COMPLETO en una sola operación:
-- 1. Inserta el contrato
-- 2. Crea la factura asociada
-- 3. Cambia el estado de la propiedad
-- Si CUALQUIER paso falla → se deshace TODO (ROLLBACK)
-- Si TODO sale bien → se confirma TODO (COMMIT)
-- =====================================================

USE db_proyecto;

DELIMITER //

CREATE PROCEDURE crear_contrato_completo(
    IN p_tipo_contrato INT,
    IN p_propiedad INT,
    IN p_fecha_inicio DATETIME,
    IN p_fecha_fin DATETIME,
    IN p_total DECIMAL(12,2),
    IN p_cliente INT,
    IN p_agente INT
)
BEGIN
    -- Variables para capturar errores
    DECLARE error_sql CHAR(5);
    DECLARE codigo_sql INT;
    DECLARE mensaje_sql TEXT;
    -- Variables auxiliares
    DECLARE existe INT DEFAULT 0;
    DECLARE v_nuevo_contrato_id INT;
    DECLARE v_nuevo_estado INT;

    -- =====================================================
    -- MANEJADOR DE ERRORES: si algo falla → ROLLBACK
    -- =====================================================
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Deshacer TODOS los cambios que se hicieron
        ROLLBACK;

        -- Capturar info del error
        GET DIAGNOSTICS CONDITION 1
            error_sql = RETURNED_SQLSTATE,
            codigo_sql = MYSQL_ERRNO,
            mensaje_sql = MESSAGE_TEXT;

        -- Guardar el error en logs_error
        INSERT INTO logs_error (
            tabla_afectada, procedimiento, tipo_objeto,
            codigo_error, mensaje, fecha_registro
        )
        VALUES (
            'contrato',
            'crear_contrato_completo',
            'PROCEDURE',
            codigo_sql,
            CONCAT('ROLLBACK ejecutado - ', mensaje_sql),
            NOW()
        );

        -- Re-lanzar el error
        RESIGNAL;
    END;

    -- =====================================================
    -- VALIDACIONES PREVIAS (antes de iniciar la transacción)
    -- =====================================================

    -- Validar que la propiedad exista y esté disponible
    SELECT COUNT(*) INTO existe
    FROM propiedad
    WHERE id_propiedad = p_propiedad
    AND id_estado_propiedad = 1;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La propiedad no existe o no esta disponible';
    END IF;

    -- Validar que el cliente exista
    SET existe = 0;
    SELECT COUNT(*) INTO existe FROM cliente WHERE id_cliente = p_cliente;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El cliente no existe';
    END IF;

    -- Validar que el agente exista
    SET existe = 0;
    SELECT COUNT(*) INTO existe FROM agente WHERE id_agente = p_agente;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El agente no existe';
    END IF;

    -- Validar fechas
    IF p_fecha_fin <= p_fecha_inicio THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La fecha de fin debe ser posterior a la de inicio';
    END IF;

    -- Validar total
    IF p_total <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El total debe ser mayor a cero';
    END IF;

    -- =====================================================
    -- INICIAR LA TRANSACCIÓN
    -- A partir de aquí, si algo falla, se deshace TODO
    -- =====================================================
    START TRANSACTION;

        -- PASO 1: Insertar el contrato
        INSERT INTO contrato (
            tipo_contrato_id, propiedad_id, fecha_inicio,
            fecha_fin, total, cliente_id, agente_id
        )
        VALUES (
            p_tipo_contrato, p_propiedad, p_fecha_inicio,
            p_fecha_fin, p_total, p_cliente, p_agente
        );

        -- Obtener el ID del contrato que acabamos de crear
        SET v_nuevo_contrato_id = LAST_INSERT_ID();

        -- PASO 2: Crear la factura asociada al contrato
        -- Estado 2 = pendiente (aún no se ha pagado)
        INSERT INTO factura (contrato_id, estado_factura_id, fecha_emision)
        VALUES (v_nuevo_contrato_id, 2, NOW());

        -- PASO 3: Cambiar el estado de la propiedad
        -- Venta (1) → vendida (3), Arriendo (2) → arrendada (2)
        IF p_tipo_contrato = 1 THEN
            SET v_nuevo_estado = 3;
        ELSE
            SET v_nuevo_estado = 2;
        END IF;

        UPDATE propiedad
        SET id_estado_propiedad = v_nuevo_estado
        WHERE id_propiedad = p_propiedad;

    -- =====================================================
    -- Si llegamos aquí sin errores → CONFIRMAR todo
    -- =====================================================
    COMMIT;

    -- Registrar en logs que todo salió bien
    CALL escribir_log(
        'contrato',
        'crear_contrato_completo',
        'TRANSACTION_OK',
        CONCAT(
            'Contrato #', v_nuevo_contrato_id, ' creado exitosamente',
            ' | Cliente: ', p_cliente,
            ' | Agente: ', p_agente,
            ' | Propiedad: ', p_propiedad,
            ' | Total: $', FORMAT(p_total, 0),
            ' | Factura generada automáticamente'
        )
    );

END //

DELIMITER ;

-- =====================================================
-- PRUEBAS
-- =====================================================

-- ✅ Crear contrato completo exitoso (ajustar ID de propiedad disponible)
-- CALL crear_contrato_completo(2, 4, '2025-11-01', '2026-11-01', 280000000.00, 3, 2);

-- Verificar que se creó TODO:
-- SELECT * FROM contrato ORDER BY id_contrato DESC;
-- SELECT * FROM factura ORDER BY id_factura DESC;
-- SELECT * FROM propiedad WHERE id_propiedad = 4;  -- estado debe haber cambiado
-- SELECT * FROM logs ORDER BY id_logs DESC;

-- ❌ Probar con propiedad no disponible → ROLLBACK
-- CALL crear_contrato_completo(1, 2, '2025-11-01', '2026-11-01', 100000000.00, 1, 1);
-- SELECT * FROM logs_error ORDER BY id_logs_error DESC;
-- Debería decir "ROLLBACK ejecutado - ..."