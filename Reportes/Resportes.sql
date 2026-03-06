USE db_proyecto;

CREATE TABLE IF NOT EXISTS reporte_pagos_mensual (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    periodo VARCHAR(7) NOT NULL,
    id_contrato INT NOT NULL,
    nombre_cliente VARCHAR(90),
    tipo_contrato VARCHAR(20),
    valor_contrato DECIMAL(12,2),
    total_pagado DECIMAL(12,2),
    deuda DECIMAL(12,2),
    generado_el DATETIME DEFAULT NOW()
);

DELIMITER //

CREATE EVENT reporte_deudas_mensual
ON SCHEDULE
    EVERY 1 MONTH
    STARTS LAST_DAY(CURRENT_DATE) + INTERVAL 1 DAY
DO
BEGIN
    DECLARE fin BOOLEAN DEFAULT FALSE;
    DECLARE v_contrato INT;
    DECLARE v_cliente INT;
    DECLARE v_tipo INT;
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_nombre VARCHAR(90);
    DECLARE v_tipo_nombre VARCHAR(20);
    DECLARE v_pagado DECIMAL(12,2);
    DECLARE v_deuda DECIMAL(12,2);
    DECLARE v_periodo VARCHAR(7);

    DECLARE recorrer CURSOR FOR
        SELECT id_contrato, cliente_id, tipo_contrato_id, total
        FROM contrato;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET fin = TRUE;

    SET v_periodo = DATE_FORMAT(NOW(), '%Y-%m');

    OPEN recorrer;

    leer: LOOP
        FETCH recorrer INTO v_contrato, v_cliente, v_tipo, v_total;

        IF fin THEN
            LEAVE leer;
        END IF;

        SELECT CONCAT(p.nombre, ' ', p.apellido)
        INTO v_nombre
        FROM personas p
        WHERE p.id_persona = v_cliente;

        SELECT nombre INTO v_tipo_nombre
        FROM tipo_contrato
        WHERE id_tipo_contrato = v_tipo;

        SELECT COALESCE(SUM(pa.monto), 0)
        INTO v_pagado
        FROM pago pa
        INNER JOIN factura f ON pa.factura_id = f.id_factura
        WHERE f.contrato_id = v_contrato
        AND pa.monto > 0;

        SET v_deuda = v_total - v_pagado;

        IF v_deuda > 0 THEN
            INSERT INTO reporte_pagos_mensual
                (periodo, id_contrato, nombre_cliente, tipo_contrato, valor_contrato, total_pagado, deuda)
            VALUES
                (v_periodo, v_contrato, v_nombre, v_tipo_nombre, v_total, v_pagado, v_deuda);
        END IF;

    END LOOP leer;

    CLOSE recorrer;
END //

DELIMITER ;

Alter event reportes_deudas_mensual
on schedule
    every 1 minute
    start now()