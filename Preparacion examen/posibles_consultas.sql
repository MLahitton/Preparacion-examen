-- =====================================================
-- ARCHIVO: Consultas complejas que pueden caer en examen
-- Contiene 10 consultas con subconsultas, JOINs,
-- funciones de agregado y combinaciones avanzadas
-- =====================================================

USE db_proyecto;

-- =====================================================
-- 1. Top 3 propiedades más caras por ciudad
-- Usa: subconsulta con variable de ranking
-- =====================================================
SELECT
    ciudad,
    direccion,
    precio_formateado
FROM (
    SELECT
        c.nombre AS ciudad,
        p.direccion,
        FORMAT(p.precio, 0) AS precio_formateado,
        p.precio,
        -- ROW_NUMBER asigna un número 1, 2, 3... por cada ciudad
        -- ordenando de mayor a menor precio
        ROW_NUMBER() OVER (PARTITION BY c.nombre ORDER BY p.precio DESC) AS ranking
    FROM propiedad p
    INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
) ranked
-- Solo las 3 más caras de cada ciudad
WHERE ranking <= 3;


-- =====================================================
-- 2. Cliente que más dinero ha invertido (total de contratos)
-- Usa: GROUP BY + ORDER BY + LIMIT
-- =====================================================
SELECT
    CONCAT(p.nombre, ' ', p.apellido) AS cliente,
    COUNT(c.id_contrato) AS cantidad_contratos,
    FORMAT(SUM(c.total), 0) AS total_invertido
FROM contrato c
INNER JOIN personas p ON c.cliente_id = p.id_persona
GROUP BY c.cliente_id, p.nombre, p.apellido
ORDER BY SUM(c.total) DESC
LIMIT 1;


-- =====================================================
-- 3. Agente que más comisión ha generado
-- Usa: funciones del sistema + GROUP BY
-- =====================================================
SELECT
    CONCAT(p.nombre, ' ', p.apellido) AS agente,
    a.comision AS porcentaje,
    COUNT(c.id_contrato) AS contratos,
    FORMAT(SUM(c.total * a.comision / 100), 0) AS total_comisiones
FROM contrato c
INNER JOIN agente a ON c.agente_id = a.id_agente
INNER JOIN personas p ON a.id_agente = p.id_persona
GROUP BY a.id_agente, p.nombre, p.apellido, a.comision
ORDER BY SUM(c.total * a.comision / 100) DESC
LIMIT 1;


-- =====================================================
-- 4. Contratos que vencen el próximo mes
-- Usa: funciones de fecha
-- =====================================================
SELECT
    c.id_contrato,
    CONCAT(p.nombre, ' ', p.apellido) AS cliente,
    pr.direccion AS propiedad,
    c.fecha_fin,
    DATEDIFF(c.fecha_fin, CURRENT_DATE) AS dias_restantes
FROM contrato c
INNER JOIN personas p ON c.cliente_id = p.id_persona
INNER JOIN propiedad pr ON c.propiedad_id = pr.id_propiedad
-- Filtro: fecha_fin está entre hoy y dentro de 30 días
WHERE c.fecha_fin BETWEEN CURRENT_DATE AND DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY)
ORDER BY c.fecha_fin ASC;


-- =====================================================
-- 5. Propiedades que NUNCA han tenido contrato
-- Usa: LEFT JOIN + IS NULL (o NOT EXISTS)
-- =====================================================
SELECT
    p.id_propiedad,
    p.direccion,
    FORMAT(p.precio, 0) AS precio,
    tp.nombre AS tipo,
    c.nombre AS ciudad
FROM propiedad p
INNER JOIN tipo_propiedad tp ON p.id_tipo_propiedad = tp.id_tipo_propiedad
INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
-- LEFT JOIN: trae todas las propiedades aunque no tengan contrato
LEFT JOIN contrato co ON p.id_propiedad = co.propiedad_id
-- WHERE IS NULL: filtra solo las que NO tienen contrato
WHERE co.id_contrato IS NULL;


-- =====================================================
-- 6. Resumen de ingresos por tipo de contrato
-- Usa: GROUP BY + CASE + funciones de agregado
-- =====================================================
SELECT
    tc.nombre AS tipo_contrato,
    COUNT(*) AS cantidad,
    FORMAT(SUM(c.total), 0) AS ingreso_total,
    FORMAT(AVG(c.total), 0) AS ingreso_promedio,
    FORMAT(MIN(c.total), 0) AS contrato_menor,
    FORMAT(MAX(c.total), 0) AS contrato_mayor
FROM contrato c
INNER JOIN tipo_contrato tc ON c.tipo_contrato_id = tc.id_tipo_contrato
GROUP BY tc.nombre;


-- =====================================================
-- 7. Porcentaje de propiedades por estado
-- Usa: subconsulta + cálculo de porcentaje
-- =====================================================
SELECT
    ep.nombre AS estado,
    COUNT(*) AS cantidad,
    -- Calcular el porcentaje sobre el total de propiedades
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM propiedad),
        1
    ) AS porcentaje
FROM propiedad p
INNER JOIN estado_propiedad ep ON p.id_estado_propiedad = ep.id_estado_propiedad
GROUP BY ep.nombre
ORDER BY cantidad DESC;


-- =====================================================
-- 8. Clientes con TODA su información de contacto
--    y resumen financiero
-- Usa: múltiples LEFT JOINs + subconsultas
-- =====================================================
SELECT
    CONCAT(p.nombre, ' ', p.apellido) AS cliente,
    CONCAT(d.tipo, ': ', d.numero) AS documento,
    CONCAT(e.nombre_email, '@', e.dominio) AS email,
    CONCAT(t.codigo, ' ', t.numero) AS telefono,
    COALESCE(resumen.total_contratos, 0) AS total_contratos,
    FORMAT(COALESCE(resumen.total_invertido, 0), 0) AS total_invertido,
    FORMAT(COALESCE(resumen.total_pagado, 0), 0) AS total_pagado,
    FORMAT(COALESCE(resumen.total_invertido, 0) - COALESCE(resumen.total_pagado, 0), 0) AS deuda_total
FROM personas p
INNER JOIN cliente cl ON p.id_persona = cl.id_cliente
LEFT JOIN documento d ON p.documento_id_documento = d.id_documento
LEFT JOIN email e ON p.email_id_email = e.id_email
LEFT JOIN telefono t ON p.id_persona = t.personas_id_persona
LEFT JOIN (
    -- Subconsulta que calcula el resumen financiero por cliente
    SELECT
        c.cliente_id,
        COUNT(c.id_contrato) AS total_contratos,
        SUM(c.total) AS total_invertido,
        COALESCE(SUM(pag.pagado), 0) AS total_pagado
    FROM contrato c
    LEFT JOIN (
        SELECT f.contrato_id, SUM(pa.monto) AS pagado
        FROM pago pa
        INNER JOIN factura f ON pa.factura_id = f.id_factura
        WHERE pa.monto > 0
        GROUP BY f.contrato_id
    ) pag ON c.id_contrato = pag.contrato_id
    GROUP BY c.cliente_id
) resumen ON cl.id_cliente = resumen.cliente_id;


-- =====================================================
-- 9. Historial completo de una propiedad específica
--    (cambiar el ID según lo que quieras consultar)
-- Usa: UNION ALL para combinar datos de distintas fuentes
-- =====================================================
SELECT 'DATOS' AS seccion, p.direccion AS detalle,
       FORMAT(p.precio, 0) AS valor, ep.nombre AS estado, NULL AS fecha
FROM propiedad p
INNER JOIN estado_propiedad ep ON p.id_estado_propiedad = ep.id_estado_propiedad
WHERE p.id_propiedad = 1

UNION ALL

SELECT 'CONTRATO', CONCAT('Contrato #', c.id_contrato, ' - ', tc.nombre),
       FORMAT(c.total, 0), CONCAT(pe.nombre, ' ', pe.apellido), c.fecha_inicio
FROM contrato c
INNER JOIN tipo_contrato tc ON c.tipo_contrato_id = tc.id_tipo_contrato
INNER JOIN personas pe ON c.cliente_id = pe.id_persona
WHERE c.propiedad_id = 1

UNION ALL

SELECT 'LOG', accion, LEFT(descripcion, 80), procedimiento, fecha_registro
FROM logs
WHERE tabla_afectada = 'propiedad'
AND descripcion LIKE '%id_propiedad%1%'
ORDER BY fecha DESC;


-- =====================================================
-- 10. Dashboard ejecutivo completo
--     (una sola consulta que resume TODO el negocio)
-- Usa: subconsultas independientes
-- =====================================================
SELECT
    (SELECT COUNT(*) FROM propiedad) AS total_propiedades,
    (SELECT COUNT(*) FROM propiedad WHERE id_estado_propiedad = 1) AS disponibles,
    (SELECT COUNT(*) FROM propiedad WHERE id_estado_propiedad = 2) AS arrendadas,
    (SELECT COUNT(*) FROM propiedad WHERE id_estado_propiedad = 3) AS vendidas,
    (SELECT COUNT(*) FROM contrato) AS total_contratos,
    (SELECT FORMAT(SUM(total), 0) FROM contrato) AS valor_total_contratos,
    (SELECT COUNT(*) FROM cliente) AS total_clientes,
    (SELECT COUNT(*) FROM agente) AS total_agentes,
    (SELECT FORMAT(COALESCE(SUM(monto), 0), 0) FROM pago WHERE monto > 0) AS total_recaudado,
    (SELECT COUNT(*) FROM logs) AS total_logs,
    (SELECT COUNT(*) FROM logs_error) AS total_errores;