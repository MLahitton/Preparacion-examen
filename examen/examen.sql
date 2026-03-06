
--Consulta 1

SELECT 
    CONCAT(p.nombre, ' ', p.apellido) AS nombre_vendedor,
    COUNT(c.id_contrato) AS total_propiedades_vendidas
FROM agente a
INNER JOIN personas p ON a.id_agente = p.id_persona
INNER JOIN contrato c ON a.id_agente = c.agente_id
WHERE c.tipo_contrato_id = 1  
GROUP BY a.id_agente, p.nombre, p.apellido
ORDER BY total_propiedades_vendidas DESC;

--Consulta 2

SELECT 
    p.id_propiedad,
    p.direccion,
    FORMAT(p.precio, 0) AS precio,
    tp.nombre AS tipo,
    c.nombre AS ciudad
FROM propiedad p
INNER JOIN tipo_propiedad tp ON p.id_tipo_propiedad = tp.id_tipo_propiedad
INNER JOIN ciudad c ON p.id_ciudad = c.id_ciudad
WHERE p.id_estado_propiedad = 3  
AND p.precio BETWEEN 150000000 AND 400000000
ORDER BY p.precio ASC;


-- Consulta 3  

SELECT 
    cl.id_cliente,
    p.nombre,
    p.apellido,
    CONCAT(p.nombre, ' ', p.apellido) AS nombre_completo
FROM cliente cl
INNER JOIN personas p ON cl.id_cliente = p.id_persona
WHERE p.nombre LIKE '%Carlos%' 


-- Consulta 4

SELECT 
    CONCAT(p.nombre, ' ', p.apellido) AS nombre_vendedor,
    pr.direccion AS propiedad_vendida,
    FORMAT(pr.precio, 0) AS precio,
    ci.nombre AS ciudad,
    c.fecha_inicio AS fecha_venta,
    FORMAT(c.total, 0) AS valor_venta
FROM contrato c
INNER JOIN propiedad pr ON c.propiedad_id = pr.id_propiedad
INNER JOIN ciudad ci ON pr.id_ciudad = ci.id_ciudad
RIGHT JOIN agente a ON c.agente_id = a.id_agente 
    AND c.tipo_contrato_id = 1  
RIGHT JOIN personas p ON a.id_agente = p.id_persona 
    AND a.id_agente IS NOT NULL
WHERE EXISTS (SELECT 1 FROM agente WHERE id_agente = p.id_persona)
ORDER BY p.nombre;


-- Consulta 5

