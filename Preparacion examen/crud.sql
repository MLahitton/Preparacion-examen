-- =====================================================
-- ARCHIVO: CRUD completo para Propiedades
-- CRUD = Create (crear), Read (leer), Update (actualizar), Delete (eliminar)
--
-- Se usa Stored Procedures porque:
-- ✅ Permiten validaciones complejas (las funciones no pueden hacer INSERT/UPDATE/DELETE)
-- ✅ Permiten manejo de errores con EXIT HANDLER
-- ✅ Permiten registrar en logs cada acción
-- ✅ Permiten usar transacciones
--
-- Contiene 5 procedimientos:
-- 1. sp_crear_propiedad        → CREATE (insertar)
-- 2. sp_leer_propiedades       → READ (consultar todas o una)
-- 3. sp_actualizar_propiedad   → UPDATE (modificar)
-- 4. sp_eliminar_propiedad     → DELETE (borrar)
-- 5. sp_cambiar_estado         → UPDATE específico (cambiar estado)
-- =====================================================

USE db_proyecto;

DELIMITER //

-- =====================================================
-- 1. CREATE: sp_crear_propiedad
-- ¿Qué hace? Inserta una propiedad nueva con validaciones
-- completas y registro en logs.
-- Es similar a registrar_propiedad_segura pero más completo.
-- =====================================================
CREATE PROCEDURE sp_crear_propiedad(
    IN p_direccion VARCHAR(100),   -- Dirección de la propiedad
    IN p_precio DECIMAL(12,2),     -- Precio
    IN p_tipo INT,                 -- ID del tipo (1=casa, 2=apto, 3=local)
    IN p_estado INT,               -- ID del estado (1=disponible, 2=arrendada, 3=vendida)
    IN p_ciudad INT                -- ID de la ciudad
)
BEGIN
    -- Variables para manejo de errores
    DECLARE error_sql CHAR(5);
    DECLARE codigo_sql INT;
    DECLARE mensaje_sql TEXT;
    DECLARE existe INT DEFAULT 0;
    DECLARE v_nuevo_id INT;

    -- Manejador de errores: si algo falla → guarda en logs_error
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
            'propiedad', 'sp_crear_propiedad', 'PROCEDURE',
            codigo_sql, mensaje_sql, NOW()
        );
        RESIGNAL;
    END;

    -- Validación: dirección no vacía
    IF p_direccion IS NULL OR TRIM(p_direccion) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CREAR: La direccion no puede estar vacia';
    END IF;

    -- Validación: precio mayor a 0
    IF p_precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CREAR: El precio debe ser mayor a cero';
    END IF;

    -- Validación: tipo de propiedad existe
    SELECT COUNT(*) INTO existe FROM tipo_propiedad WHERE id_tipo_propiedad = p_tipo;
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CREAR: El tipo de propiedad no existe';
    END IF;

    -- Validación: estado de propiedad existe
    SET existe = 0;
    SELECT COUNT(*) INTO existe FROM estado_propiedad WHERE id_estado_propiedad = p_estado;
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CREAR: El estado de propiedad no existe';
    END IF;

    -- Validación: ciudad existe
    SET existe = 0;
    SELECT COUNT(*) INTO existe FROM ciudad WHERE id_ciudad = p_ciudad;
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CREAR: La ciudad no existe';
    END IF;

    -- Validación: no duplicar dirección en la misma ciudad
    SET existe = 0;
    SELECT COUNT(*) INTO existe
    FROM propiedad
    WHERE direccion = p_direccion AND id_ciudad = p_ciudad;
    IF existe > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CREAR: Ya existe una propiedad con esa direccion en esa ciudad';
    END IF;

    -- Todo válido → Insertar
    INSERT INTO propiedad (direccion, precio, id_tipo_propiedad, id_estado_propiedad, id_ciudad)
    VALUES (p_direccion, p_precio, p_tipo, p_estado, p_ciudad);

    -- Obtener el ID de la propiedad recién creada
    SET v_nuevo_id = LAST_INSERT_ID();

    -- Mostrar la propiedad creada como confirmación
    SELECT
        p.id_propiedad,
        p.direccion,
        FORMAT(p.precio, 0) AS precio,
        tp.nombre AS tipo,
        ep.nombre AS estado,
        c.nombre AS ciudad,
        'CREADA EXITOSAMENTE' AS resultado
    FROM propiedad p
    INNER JOIN tipo_propiedad tp ON p.id_tipo_propiedad = tp.id_tipo_propiedad
    INNER JOIN estado_propiedad ep ON p.id_estado_propiedad = ep.id_estado_propiedad
    INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
    WHERE p.id_propiedad = v_nuevo_id;

END //


-- =====================================================
-- 2. READ: sp_leer_propiedades
-- ¿Qué hace? Si le pasás un ID → muestra esa propiedad
-- Si le pasás NULL o 0 → muestra TODAS las propiedades
-- =====================================================
CREATE PROCEDURE sp_leer_propiedades(
    IN p_id INT  -- ID de la propiedad (NULL o 0 = todas)
)
BEGIN
    -- Si el ID es NULL o 0, mostrar todas
    IF p_id IS NULL OR p_id = 0 THEN
        SELECT
            p.id_propiedad,
            p.direccion,
            FORMAT(p.precio, 0) AS precio,
            tp.nombre AS tipo,
            ep.nombre AS estado,
            c.nombre AS ciudad
        FROM propiedad p
        INNER JOIN tipo_propiedad tp ON p.id_tipo_propiedad = tp.id_tipo_propiedad
        INNER JOIN estado_propiedad ep ON p.id_estado_propiedad = ep.id_estado_propiedad
        INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
        ORDER BY p.id_propiedad;
    ELSE
        -- Mostrar una propiedad específica con más detalle
        SELECT
            p.id_propiedad,
            p.direccion,
            p.precio AS precio_numerico,
            FORMAT(p.precio, 0) AS precio_formateado,
            tp.nombre AS tipo,
            ep.nombre AS estado,
            c.nombre AS ciudad,
            -- Verificar si tiene contrato activo
            CASE
                WHEN EXISTS (
                    SELECT 1 FROM contrato co
                    WHERE co.propiedad_id = p.id_propiedad
                    AND co.fecha_fin >= NOW()
                ) THEN 'Sí'
                ELSE 'No'
            END AS tiene_contrato_activo
        FROM propiedad p
        INNER JOIN tipo_propiedad tp ON p.id_tipo_propiedad = tp.id_tipo_propiedad
        INNER JOIN estado_propiedad ep ON p.id_estado_propiedad = ep.id_estado_propiedad
        INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
        WHERE p.id_propiedad = p_id;
    END IF;
END //


-- =====================================================
-- 3. UPDATE: sp_actualizar_propiedad
-- ¿Qué hace? Modifica la dirección, precio, tipo y/o ciudad
-- de una propiedad existente. Valida todo antes de actualizar.
-- =====================================================
CREATE PROCEDURE sp_actualizar_propiedad(
    IN p_id INT,                   -- ID de la propiedad a modificar
    IN p_direccion VARCHAR(100),   -- Nueva dirección (NULL = no cambiar)
    IN p_precio DECIMAL(12,2),     -- Nuevo precio (NULL o 0 = no cambiar)
    IN p_tipo INT,                 -- Nuevo tipo (NULL o 0 = no cambiar)
    IN p_ciudad INT                -- Nueva ciudad (NULL o 0 = no cambiar)
)
BEGIN
    DECLARE error_sql CHAR(5);
    DECLARE codigo_sql INT;
    DECLARE mensaje_sql TEXT;
    DECLARE existe INT DEFAULT 0;
    -- Variables para guardar los valores actuales
    DECLARE v_dir_actual VARCHAR(100);
    DECLARE v_precio_actual DECIMAL(12,2);
    DECLARE v_tipo_actual INT;
    DECLARE v_ciudad_actual INT;

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
            'propiedad', 'sp_actualizar_propiedad', 'PROCEDURE',
            codigo_sql, mensaje_sql, NOW()
        );
        RESIGNAL;
    END;

    -- Validar que la propiedad existe
    SELECT COUNT(*) INTO existe FROM propiedad WHERE id_propiedad = p_id;
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ACTUALIZAR: La propiedad no existe';
    END IF;

    -- Obtener los valores actuales de la propiedad
    SELECT direccion, precio, id_tipo_propiedad, id_ciudad
    INTO v_dir_actual, v_precio_actual, v_tipo_actual, v_ciudad_actual
    FROM propiedad
    WHERE id_propiedad = p_id;

    -- Si un parámetro es NULL o 0, se mantiene el valor actual
    -- Esto permite actualizar solo lo que se quiera cambiar
    IF p_direccion IS NOT NULL AND TRIM(p_direccion) != '' THEN
        SET v_dir_actual = p_direccion;
    END IF;

    IF p_precio IS NOT NULL AND p_precio > 0 THEN
        SET v_precio_actual = p_precio;
    END IF;

    IF p_tipo IS NOT NULL AND p_tipo > 0 THEN
        -- Validar que el nuevo tipo exista
        SET existe = 0;
        SELECT COUNT(*) INTO existe FROM tipo_propiedad WHERE id_tipo_propiedad = p_tipo;
        IF existe = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ACTUALIZAR: El tipo de propiedad no existe';
        END IF;
        SET v_tipo_actual = p_tipo;
    END IF;

    IF p_ciudad IS NOT NULL AND p_ciudad > 0 THEN
        -- Validar que la nueva ciudad exista
        SET existe = 0;
        SELECT COUNT(*) INTO existe FROM ciudad WHERE id_ciudad = p_ciudad;
        IF existe = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ACTUALIZAR: La ciudad no existe';
        END IF;
        SET v_ciudad_actual = p_ciudad;
    END IF;

    -- Ejecutar el UPDATE con los valores finales
    UPDATE propiedad
    SET direccion = v_dir_actual,
        precio = v_precio_actual,
        id_tipo_propiedad = v_tipo_actual,
        id_ciudad = v_ciudad_actual
    WHERE id_propiedad = p_id;

    -- Registrar en logs
    CALL escribir_log(
        'propiedad',
        'sp_actualizar_propiedad',
        'UPDATE',
        CONCAT('Propiedad #', p_id, ' actualizada ',
               '| Dir: ', v_dir_actual,
               ' | Precio: $', FORMAT(v_precio_actual, 0),
               ' | Tipo: ', v_tipo_actual,
               ' | Ciudad: ', v_ciudad_actual)
    );

    -- Mostrar el resultado actualizado
    CALL sp_leer_propiedades(p_id);

END //


-- =====================================================
-- 4. DELETE: sp_eliminar_propiedad
-- ¿Qué hace? Elimina una propiedad SOLO si no tiene
-- contratos asociados. Si tiene → error.
-- =====================================================
CREATE PROCEDURE sp_eliminar_propiedad(
    IN p_id INT  -- ID de la propiedad a eliminar
)
BEGIN
    DECLARE error_sql CHAR(5);
    DECLARE codigo_sql INT;
    DECLARE mensaje_sql TEXT;
    DECLARE existe INT DEFAULT 0;
    DECLARE tiene_contratos INT DEFAULT 0;
    -- Variables para guardar info antes de borrar (para el log)
    DECLARE v_direccion VARCHAR(100);
    DECLARE v_precio DECIMAL(12,2);

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
            'propiedad', 'sp_eliminar_propiedad', 'PROCEDURE',
            codigo_sql, mensaje_sql, NOW()
        );
        RESIGNAL;
    END;

    -- Validar que la propiedad existe
    SELECT COUNT(*) INTO existe FROM propiedad WHERE id_propiedad = p_id;
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ELIMINAR: La propiedad no existe';
    END IF;

    -- Validar que NO tenga contratos asociados
    SELECT COUNT(*) INTO tiene_contratos
    FROM contrato
    WHERE propiedad_id = p_id;

    IF tiene_contratos > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ELIMINAR: No se puede borrar, la propiedad tiene contratos asociados';
    END IF;

    -- Guardar info antes de borrar (para el log)
    SELECT direccion, precio
    INTO v_direccion, v_precio
    FROM propiedad
    WHERE id_propiedad = p_id;

    -- Eliminar la propiedad
    DELETE FROM propiedad WHERE id_propiedad = p_id;

    -- Registrar en logs
    CALL escribir_log(
        'propiedad',
        'sp_eliminar_propiedad',
        'DELETE',
        CONCAT('Propiedad #', p_id, ' eliminada',
               ' | Dir: ', v_direccion,
               ' | Precio: $', FORMAT(v_precio, 0))
    );

    -- Confirmar al usuario
    SELECT CONCAT('Propiedad #', p_id, ' (', v_direccion, ') eliminada exitosamente') AS resultado;

END //


-- =====================================================
-- 5. CAMBIAR ESTADO: sp_cambiar_estado
-- ¿Qué hace? Cambia el estado de una propiedad
-- (disponible, arrendada, vendida) con validación
-- =====================================================
CREATE PROCEDURE sp_cambiar_estado(
    IN p_id INT,       -- ID de la propiedad
    IN p_estado INT    -- Nuevo estado (1=disponible, 2=arrendada, 3=vendida)
)
BEGIN
    DECLARE error_sql CHAR(5);
    DECLARE codigo_sql INT;
    DECLARE mensaje_sql TEXT;
    DECLARE existe INT DEFAULT 0;
    DECLARE v_estado_actual INT;

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
            'propiedad', 'sp_cambiar_estado', 'PROCEDURE',
            codigo_sql, mensaje_sql, NOW()
        );
        RESIGNAL;
    END;

    -- Validar que la propiedad existe
    SELECT COUNT(*) INTO existe FROM propiedad WHERE id_propiedad = p_id;
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ESTADO: La propiedad no existe';
    END IF;

    -- Validar que el estado existe
    SET existe = 0;
    SELECT COUNT(*) INTO existe FROM estado_propiedad WHERE id_estado_propiedad = p_estado;
    IF existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ESTADO: El estado indicado no existe (1=disponible, 2=arrendada, 3=vendida)';
    END IF;

    -- Verificar que no sea el mismo estado actual
    SELECT id_estado_propiedad INTO v_estado_actual
    FROM propiedad
    WHERE id_propiedad = p_id;

    IF v_estado_actual = p_estado THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ESTADO: La propiedad ya tiene ese estado';
    END IF;

    -- Cambiar el estado
    -- Nota: este UPDATE activa el trigger "vigilar_propiedad" que registra en logs
    UPDATE propiedad
    SET id_estado_propiedad = p_estado
    WHERE id_propiedad = p_id;

    -- Mostrar el resultado
    CALL sp_leer_propiedades(p_id);

END //

DELIMITER ;


-- =====================================================
-- PRUEBAS DEL CRUD COMPLETO
-- =====================================================

-- -----------------------------------------------
-- CREATE: Crear una propiedad nueva
-- -----------------------------------------------
-- CALL sp_crear_propiedad('Carrera 50 #20-15', 380000000.00, 2, 1, 2);

-- -----------------------------------------------
-- READ: Leer propiedades
-- -----------------------------------------------
-- Todas las propiedades:
-- CALL sp_leer_propiedades(NULL);
-- CALL sp_leer_propiedades(0);

-- Una propiedad específica:
-- CALL sp_leer_propiedades(1);

-- -----------------------------------------------
-- UPDATE: Actualizar propiedad
-- -----------------------------------------------
-- Cambiar solo el precio (los demás en NULL = no cambiar):
-- CALL sp_actualizar_propiedad(1, NULL, 500000000.00, NULL, NULL);

-- Cambiar dirección y ciudad:
-- CALL sp_actualizar_propiedad(1, 'Nueva Dirección #999', NULL, NULL, 3);

-- -----------------------------------------------
-- CAMBIAR ESTADO:
-- -----------------------------------------------
-- CALL sp_cambiar_estado(1, 2);  -- Pasar a "arrendada"
-- CALL sp_cambiar_estado(1, 1);  -- Volver a "disponible"

-- -----------------------------------------------
-- DELETE: Eliminar propiedad (solo si no tiene contratos)
-- -----------------------------------------------
-- Primero crear una propiedad de prueba para borrarla:
-- CALL sp_crear_propiedad('Temporal para borrar', 100000000.00, 1, 1, 1);
-- Luego borrarla (usar el ID que devolvió):
-- CALL sp_eliminar_propiedad(ID_AQUI);

-- ❌ Intentar borrar propiedad con contrato → ERROR
-- CALL sp_eliminar_propiedad(1);

-- -----------------------------------------------
-- Verificar logs de todo lo que hicimos:
-- -----------------------------------------------
-- SELECT * FROM logs ORDER BY id_logs DESC;
-- SELECT * FROM logs_error ORDER BY id_logs_error DESC;