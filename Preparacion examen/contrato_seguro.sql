-- =====================================================
-- PROCEDIMIENTO: registrar_contrato_seguro
-- ¿Qué hace? Inserta un contrato nuevo validando TODO
-- antes de insertarlo, y si algo falla lo guarda en logs_error
-- =====================================================

USE db_proyecto;

DELIMITER //

CREATE PROCEDURE registrar_contrato_seguro(
    -- Parámetros que recibe: todos los datos necesarios para crear un contrato
    IN p_tipo_contrato INT,     -- 1 = venta, 2 = arriendo
    IN p_propiedad INT,         -- ID de la propiedad
    IN p_fecha_inicio DATETIME, -- Cuándo empieza el contrato
    IN p_fecha_fin DATETIME,    -- Cuándo termina el contrato
    IN p_total DECIMAL(12,2),   -- Valor total del contrato
    IN p_cliente INT,           -- ID del cliente
    IN p_agente INT             -- ID del agente
)
BEGIN
    -- Variables para capturar errores
    DECLARE error_sql CHAR(5);
    DECLARE codigo_sql INT;
    DECLARE mensaje_sql TEXT;
    -- Variable auxiliar para verificar si algo existe
    DECLARE existe INT DEFAULT 0;

    -- =====================================================
    -- MANEJADOR DE ERRORES (como un try-catch)
    -- Si algo falla, guarda el error en logs_error y lo re-lanza
    -- =====================================================
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Captura la información del error
        GET DIAGNOSTICS CONDITION 1
            error_sql = RETURNED_SQLSTATE,
            codigo_sql = MYSQL_ERRNO,
            mensaje_sql = MESSAGE_TEXT;

        -- Guarda el error en la tabla logs_error
        INSERT INTO logs_error (
            tabla_afectada, procedimiento, tipo_objeto,
            codigo_error, mensaje, fecha_registro
        )
        VALUES (
            'contrato',
            'registrar_contrato_seguro',
            'PROCEDURE',
            codigo_sql,
            mensaje_sql,
            NOW()
        );

        -- Re-lanza el error para que el usuario también lo vea
        RESIGNAL;
    END;

    -- =====================================================
    -- VALIDACIÓN 1: El tipo de contrato debe existir
    -- =====================================================
    SELECT COUNT(*) INTO existe
    FROM tipo_contrato
    WHERE id_tipo_contrato = p_tipo_contrato;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El tipo de contrato no existe (solo: 1=venta, 2=arriendo)';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 2: La propiedad debe existir
    -- =====================================================
    SET existe = 0;
    SELECT COUNT(*) INTO existe
    FROM propiedad
    WHERE id_propiedad = p_propiedad;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La propiedad indicada no existe';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 3: La propiedad debe estar disponible (estado 1)
    -- No podés hacer un contrato de una casa que ya está vendida
    -- =====================================================
    SET existe = 0;
    SELECT COUNT(*) INTO existe
    FROM propiedad
    WHERE id_propiedad = p_propiedad
    AND id_estado_propiedad = 1;  -- 1 = disponible

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La propiedad no esta disponible (ya esta arrendada o vendida)';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 4: La propiedad NO debe tener un contrato activo
    -- =====================================================
    SET existe = 0;
    SELECT COUNT(*) INTO existe
    FROM contrato
    WHERE propiedad_id = p_propiedad
    AND fecha_fin >= NOW();  -- Si la fecha_fin es futura, el contrato sigue activo

    IF existe > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La propiedad ya tiene un contrato activo vigente';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 5: El cliente debe existir
    -- =====================================================
    SET existe = 0;
    SELECT COUNT(*) INTO existe
    FROM cliente
    WHERE id_cliente = p_cliente;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El cliente indicado no existe';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 6: El agente debe existir
    -- =====================================================
    SET existe = 0;
    SELECT COUNT(*) INTO existe
    FROM agente
    WHERE id_agente = p_agente;

    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El agente indicado no existe';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 7: La fecha de fin debe ser mayor a la de inicio
    -- =====================================================
    IF p_fecha_fin <= p_fecha_inicio THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La fecha de fin debe ser posterior a la fecha de inicio';
    END IF;

    -- =====================================================
    -- VALIDACIÓN 8: El total debe ser mayor a 0
    -- =====================================================
    IF p_total <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El valor total del contrato debe ser mayor a cero';
    END IF;

    -- =====================================================
    -- Si TODAS las validaciones pasaron → insertar el contrato
    -- =====================================================
    INSERT INTO contrato (
        tipo_contrato_id, propiedad_id, fecha_inicio,
        fecha_fin, total, cliente_id, agente_id
    )
    VALUES (
        p_tipo_contrato, p_propiedad, p_fecha_inicio,
        p_fecha_fin, p_total, p_cliente, p_agente
    );

END //

DELIMITER ;

-- =====================================================
-- PRUEBAS
-- =====================================================

-- ✅ Prueba exitosa (usar una propiedad disponible, ajustar IDs según tus datos)
-- CALL registrar_contrato_seguro(2, 4, '2025-09-01', '2026-09-01', 300000000.00, 3, 1);

-- ❌ Propiedad no existe
-- CALL registrar_contrato_seguro(1, 999, '2025-09-01', '2026-09-01', 300000000.00, 1, 1);

-- ❌ Cliente no existe
-- CALL registrar_contrato_seguro(1, 4, '2025-09-01', '2026-09-01', 300000000.00, 999, 1);

-- ❌ Fecha fin antes que fecha inicio
-- CALL registrar_contrato_seguro(1, 4, '2026-09-01', '2025-01-01', 300000000.00, 1, 1);

-- ❌ Total negativo
-- CALL registrar_contrato_seguro(1, 4, '2025-09-01', '2026-09-01', -100.00, 1, 1);

-- Ver errores capturados:
-- SELECT * FROM logs_error ORDER BY id_logs_error DESC;