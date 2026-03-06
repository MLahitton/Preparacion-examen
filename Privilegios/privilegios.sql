USE db_proyecto;

CREATE USER IF NOT EXISTS 'administrador'@'localhost' IDENTIFIED BY '111111';
GRANT ALL PRIVILEGES ON db_proyecto.* TO 'administrador'@'localhost';

CREATE USER IF NOT EXISTS 'agente_inmobiliario'@'localhost' IDENTIFIED BY '1234';

GRANT SELECT, INSERT, UPDATE ON db_proyecto.propiedad TO 'agente_inmobiliario'@'localhost';
GRANT SELECT, INSERT, UPDATE ON db_proyecto.contrato TO 'agente_inmobiliario'@'localhost';
GRANT SELECT, INSERT, UPDATE ON db_proyecto.personas TO 'agente_inmobiliario'@'localhost';
GRANT SELECT, INSERT, UPDATE ON db_proyecto.cliente TO 'agente_inmobiliario'@'localhost';
GRANT SELECT, INSERT ON db_proyecto.telefono TO 'agente_inmobiliario'@'localhost';

GRANT SELECT ON db_proyecto.tipo_propiedad TO 'agente_inmobiliario'@'localhost';
GRANT SELECT ON db_proyecto.estado_propiedad TO 'agente_inmobiliario'@'localhost';
GRANT SELECT ON db_proyecto.ciudad TO 'agente_inmobiliario'@'localhost';
GRANT SELECT ON db_proyecto.tipo_contrato TO 'agente_inmobiliario'@'localhost';

CREATE USER IF NOT EXISTS 'contador'@'localhost' IDENTIFIED BY '99999';

GRANT SELECT, INSERT, UPDATE ON db_proyecto.factura TO 'contador'@'localhost';
GRANT SELECT, INSERT, UPDATE ON db_proyecto.pago TO 'contador'@'localhost';
GRANT SELECT, INSERT ON db_proyecto.tipo_pago TO 'contador'@'localhost';

GRANT SELECT ON db_proyecto.contrato TO 'contador'@'localhost';
GRANT SELECT ON db_proyecto.estado_financiero TO 'contador'@'localhost';
GRANT SELECT ON db_proyecto.reporte_pagos_mensual TO 'contador'@'localhost';

FLUSH PRIVILEGES;