-- =====================================================
-- ARCHIVO: Nuevas vistas para el sistema
-- Contiene 3 vistas:
-- 1. vw_clientes_morosos → Clientes que deben plata
-- 2. vw_agentes_rendimiento → Ranking de agentes
-- 3. vw_propiedades_disponibles → Propiedades libres con toda su info
-- =====================================================

USE db_proyecto;

-- =====================================================
-- VISTA 1: vw_clientes_morosos
-- ¿Qué muestra? Todos los clientes que tienen deuda pendiente
-- Incluye: nombre, documento, email, teléfono, cuánto deben,
-- de qué contrato y qué propiedad es
-- Útil para: llamar a los clientes que no han pagado
-- =====================================================
CREATE VIEW vw_clientes_morosos AS
SELECT
    -- Datos del cliente
    p.id_persona AS id_cliente,
    CONCAT(p.nombre, ' ', p.apellido) AS nombre_completo,
    CONCAT(e.nombre_email, '@', e.dominio) AS email,
    CONCAT(t.codigo, ' ', t.numero) AS telefono,
    -- Datos del contrato
    c.id_contrato,
    tc.nombre AS tipo_contrato,
    pr.direccion AS propiedad,
    -- Datos financieros
    FORMAT(c.total, 0) AS valor_contrato,
    FORMAT(COALESCE(pagos.total_pagado, 0), 0) AS total_pagado,
    FORMAT(c.total - COALESCE(pagos.total_pagado, 0), 0) AS deuda_pendiente,
    -- Porcentaje de avance del pago
    ROUND(COALESCE(pagos.total_pagado, 0) / c.total * 100, 1) AS porcentaje_pagado
FROM contrato c
-- Unir con el cliente y sus datos personales
INNER JOIN personas p ON c.cliente_id = p.id_persona
LEFT JOIN email e ON p.email_id_email = e.id_email
LEFT JOIN telefono t ON p.id_persona = t.personas_id_persona
-- Unir con el tipo de contrato y la propiedad
INNER JOIN tipo_contrato tc ON c.tipo_contrato_id = tc.id_tipo_contrato
INNER JOIN propiedad pr ON c.propiedad_id = pr.id_propiedad
-- Subconsulta que suma los pagos por contrato
LEFT JOIN (
    SELECT f.contrato_id, SUM(pa.monto) AS total_pagado
    FROM pago pa
    INNER JOIN factura f ON pa.factura_id = f.id_factura
    WHERE pa.monto > 0
    GROUP BY f.contrato_id
) pagos ON c.id_contrato = pagos.contrato_id
-- FILTRO CLAVE: solo contratos donde la deuda es mayor a 0
WHERE c.total - COALESCE(pagos.total_pagado, 0) > 0;


-- =====================================================
-- VISTA 2: vw_agentes_rendimiento
-- ¿Qué muestra? Un ranking de agentes con:
-- cantidad de contratos gestionados, total de dinero manejado,
-- comisiones generadas, y promedio por contrato
-- Útil para: saber quién es el mejor agente
-- =====================================================
CREATE VIEW vw_agentes_rendimiento AS
SELECT
    -- Datos del agente
    a.id_agente,
    CONCAT(p.nombre, ' ', p.apellido) AS nombre_agente,
    CONCAT(a.comision, '%') AS porcentaje_comision,
    -- Métricas de rendimiento
    COUNT(c.id_contrato) AS total_contratos,
    FORMAT(COALESCE(SUM(c.total), 0), 0) AS total_dinero_gestionado,
    FORMAT(COALESCE(AVG(c.total), 0), 0) AS promedio_por_contrato,
    -- Comisiones generadas (total de cada contrato × porcentaje del agente)
    FORMAT(COALESCE(SUM(c.total * a.comision / 100), 0), 0) AS total_comisiones_ganadas
FROM agente a
-- Unir con datos personales del agente
INNER JOIN personas p ON a.id_agente = p.id_persona
-- LEFT JOIN con contratos porque un agente puede no tener contratos
LEFT JOIN contrato c ON a.id_agente = c.agente_id
-- Agrupar por agente para que las funciones de agregado funcionen
GROUP BY a.id_agente, p.nombre, p.apellido, a.comision
-- Ordenar del que más dinero gestiona al que menos
ORDER BY SUM(c.total) DESC;


-- =====================================================
-- VISTA 3: vw_propiedades_disponibles
-- ¿Qué muestra? Solo las propiedades con estado "disponible"
-- con toda su información lista para mostrar a un cliente
-- Útil para: cuando un cliente pregunta "¿qué hay disponible?"
-- =====================================================
CREATE VIEW vw_propiedades_disponibles AS
SELECT
    p.id_propiedad,
    p.direccion,
    FORMAT(p.precio, 0) AS precio,
    tp.nombre AS tipo,
    c.nombre AS ciudad,
    -- Verificar si la propiedad alguna vez tuvo contrato
    CASE
        WHEN EXISTS (
            SELECT 1 FROM contrato co WHERE co.propiedad_id = p.id_propiedad
        ) THEN 'Sí (contrato anterior finalizado)'
        ELSE 'No (nueva en el sistema)'
    END AS tuvo_contrato_antes
FROM propiedad p
INNER JOIN tipo_propiedad tp ON p.id_tipo_propiedad = tp.id_tipo_propiedad
INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
-- FILTRO CLAVE: solo propiedades disponibles (estado 1)
WHERE p.id_estado_propiedad = 1
-- Ordenar por precio de menor a mayor
ORDER BY p.precio ASC;

-- =====================================================
-- PRUEBAS
-- =====================================================

-- Ver clientes morosos (contratos 1, 3 y 5 que no han pagado)
-- SELECT * FROM vw_clientes_morosos;

-- Ver ranking de agentes
-- SELECT * FROM vw_agentes_rendimiento;

-- Ver propiedades disponibles
-- SELECT * FROM vw_propiedades_disponibles;