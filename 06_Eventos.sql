USE ecommerce_db;

-- ---------------------------------------------------------------------
-- Activación del planificador de eventos de MySQL (viene apagado por
-- defecto). Debe ejecutarse con un usuario con privilegio SUPER/
-- SYSTEM_VARIABLES_ADMIN, o configurarse en el my.cnf del servidor.
-- ---------------------------------------------------------------------
SET GLOBAL event_scheduler = ON;

-- ---------------------------------------------------------------------
-- Tabla de reporte semanal, exigida explícitamente por el enunciado.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte          INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio       DATE NOT NULL,
    semana_fin          DATE NOT NULL,
    cantidad_ventas     INT NOT NULL,
    monto_total_vendido DECIMAL(14,2) NOT NULL,
    fecha_generacion    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- Tablas auxiliares adicionales requeridas por otros eventos de este
-- bloque (no definidas en el esquema original de la sección 2).
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS promociones (
    id_promocion        INT AUTO_INCREMENT PRIMARY KEY,
    codigo               VARCHAR(30) NOT NULL UNIQUE,
    porcentaje_descuento DECIMAL(5,2) NOT NULL,
    fecha_expiracion    DATETIME NOT NULL,
    activa               BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE = InnoDB;

ALTER TABLE clientes
    ADD COLUMN nivel_lealtad VARCHAR(10) NOT NULL DEFAULT 'Bronce';

CREATE TABLE IF NOT EXISTS lista_reabastecimiento (
    id_item          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto      INT NOT NULL,
    stock_actual     INT NOT NULL,
    unidades_a_pedir INT NOT NULL,
    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS resumen_ventas_diarias (
    id_resumen           INT AUTO_INCREMENT PRIMARY KEY,
    fecha                DATE NOT NULL UNIQUE,
    cantidad_ventas      INT NOT NULL,
    monto_total_vendido  DECIMAL(14,2) NOT NULL,
    fecha_generacion     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS inconsistencias_detectadas (
    id_inconsistencia INT AUTO_INCREMENT PRIMARY KEY,
    descripcion        VARCHAR(255) NOT NULL,
    referencia_id       INT NULL,
    fecha_deteccion     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS cupones_cumpleanos (
    id_cupon         INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente       INT NOT NULL,
    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS ranking_productos (
    id_producto        INT NOT NULL PRIMARY KEY,
    unidades_vendidas  INT NOT NULL,
    posicion            INT NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                         ON UPDATE CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS productos_backup LIKE productos;
CREATE TABLE IF NOT EXISTS ventas_backup LIKE ventas;
CREATE TABLE IF NOT EXISTS clientes_backup LIKE clientes;

CREATE TABLE IF NOT EXISTS actividad_sospechosa (
    id_alerta        INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente       INT NOT NULL,
    motivo           VARCHAR(255) NOT NULL,
    fecha_deteccion  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS reporte_proveedores_mensual (
    id_reporte         INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor       INT NOT NULL,
    anio               INT NOT NULL,
    mes                INT NOT NULL,
    unidades_vendidas  INT NOT NULL,
    ingresos_generados DECIMAL(14,2) NOT NULL,
    fecha_generacion   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS tamano_bd_historico (
    id_registro    INT AUTO_INCREMENT PRIMARY KEY,
    tamano_mb       DECIMAL(10,2) NOT NULL,
    fecha_registro  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS kpis_mensuales (
    id_kpi              INT AUTO_INCREMENT PRIMARY KEY,
    anio                INT NOT NULL,
    mes                 INT NOT NULL,
    total_ventas        INT NOT NULL,
    monto_total_vendido DECIMAL(14,2) NOT NULL,
    clientes_nuevos     INT NOT NULL,
    fecha_generacion    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

-- MySQL no soporta vistas materializadas de forma nativa. Como
-- workaround se usa una tabla física que actúa como "vista
-- materializada" y se refresca periódicamente vía evento.
CREATE TABLE IF NOT EXISTS mv_resumen_categorias (
    id_categoria        INT NOT NULL PRIMARY KEY,
    nombre_categoria    VARCHAR(100) NOT NULL,
    unidades_vendidas   INT NOT NULL,
    ingresos_generados  DECIMAL(14,2) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                         ON UPDATE CURRENT_TIMESTAMP
) ENGINE = InnoDB;

DELIMITER $$

-- =====================================================================
-- 1. evt_generate_weekly_sales_report
-- Cada semana, genera el resumen de ventas de los últimos 7 días.
-- =====================================================================
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, cantidad_ventas, monto_total_vendido)
    SELECT
        DATE_SUB(CURDATE(), INTERVAL 7 DAY),
        CURDATE(),
        COUNT(*),
        COALESCE(SUM(total), 0)
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND estado <> 'Cancelado';
END$$

-- =====================================================================
-- 2. evt_cleanup_temp_tables_daily
-- Diariamente, limpia tablas de trabajo temporal. Como el proyecto no
-- usa tablas TEMPORARY persistentes propias, se vacía la tabla de
-- inconsistencias detectadas de más de 1 día como ejemplo de limpieza.
-- =====================================================================
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
    DELETE FROM inconsistencias_detectadas
    WHERE fecha_deteccion < DATE_SUB(NOW(), INTERVAL 1 DAY)$$

-- =====================================================================
-- 3. evt_archive_old_logs_monthly
-- Cada mes, archiva (aquí: elimina) registros de log_cambios_precio de
-- más de 6 meses, ya que su información relevante ya fue auditada.
-- =====================================================================
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH STARTS CURRENT_TIMESTAMP
DO
    DELETE FROM log_cambios_precio
    WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH)$$

-- =====================================================================
-- 4. evt_deactivate_expired_promotions_hourly
-- Cada hora, desactiva promociones cuya fecha de expiración ya pasó.
-- =====================================================================
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP
DO
    UPDATE promociones
        SET activa = FALSE
        WHERE fecha_expiracion < NOW()
          AND activa = TRUE$$

-- =====================================================================
-- 5. evt_recalculate_customer_loyalty_tiers_nightly
-- Cada noche, recalcula el nivel de lealtad de todos los clientes
-- usando fn_DeterminarEstadoLealtad.
-- =====================================================================
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO
    UPDATE clientes
        SET nivel_lealtad = fn_DeterminarEstadoLealtad(id_cliente)$$

-- =====================================================================
-- 6. evt_generate_reorder_list_daily
-- Diariamente, genera la lista de productos que necesitan reabastecerse.
-- =====================================================================
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
    INSERT INTO lista_reabastecimiento (id_producto, stock_actual, unidades_a_pedir)
    SELECT id_producto, stock, (umbral_minimo_stock - stock) * 2
    FROM productos
    WHERE stock < umbral_minimo_stock
      AND activo = TRUE$$

-- =====================================================================
-- 7. evt_rebuild_indexes_weekly
-- Semanalmente, reorganiza los índices de las tablas más consultadas
-- para mantener el rendimiento.
-- =====================================================================
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
BEGIN
    OPTIMIZE TABLE productos;
    OPTIMIZE TABLE ventas;
    OPTIMIZE TABLE detalle_ventas;
END$$

-- =====================================================================
-- 8. evt_suspend_inactive_accounts_quarterly
-- Cada trimestre, desactiva clientes sin compras en más de un año.
-- =====================================================================
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH STARTS CURRENT_TIMESTAMP
DO
    UPDATE clientes
        SET activo = FALSE
        WHERE (fecha_ultima_compra IS NULL OR fecha_ultima_compra < DATE_SUB(NOW(), INTERVAL 1 YEAR))
          AND fecha_registro < DATE_SUB(NOW(), INTERVAL 1 YEAR)$$

-- =====================================================================
-- 9. evt_aggregate_daily_sales_data
-- Diariamente, agrega los datos de ventas del día anterior en la tabla
-- de resumen para acelerar reportes.
-- =====================================================================
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
BEGIN
    INSERT INTO resumen_ventas_diarias (fecha, cantidad_ventas, monto_total_vendido)
    SELECT
        DATE(fecha_venta),
        COUNT(*),
        SUM(total)
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE() - INTERVAL 1 DAY
      AND estado <> 'Cancelado'
    GROUP BY DATE(fecha_venta)
    ON DUPLICATE KEY UPDATE
        cantidad_ventas = VALUES(cantidad_ventas),
        monto_total_vendido = VALUES(monto_total_vendido);
END$$

-- =====================================================================
-- 10. evt_check_data_consistency_nightly
-- Cada noche, busca ventas sin ningún detalle asociado (posible dato
-- inconsistente) y las registra.
-- =====================================================================
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO
    INSERT INTO inconsistencias_detectadas (descripcion, referencia_id)
    SELECT 'Venta sin detalle asociado', v.id_venta
    FROM ventas v
    LEFT JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    WHERE dv.id_detalle IS NULL$$

-- =====================================================================
-- 11. evt_send_birthday_greetings_daily
-- Diariamente, genera un cupón de cumpleaños para los clientes que
-- cumplen años hoy.
-- =====================================================================
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
    INSERT INTO cupones_cumpleanos (id_cliente)
    SELECT id_cliente
    FROM clientes
    WHERE MONTH(fecha_nacimiento) = MONTH(CURDATE())
      AND DAY(fecha_nacimiento) = DAY(CURDATE())$$

-- =====================================================================
-- 12. evt_update_product_rankings_hourly
-- Cada hora, recalcula el ranking de productos más vendidos.
-- =====================================================================
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM ranking_productos;

    INSERT INTO ranking_productos (id_producto, unidades_vendidas, posicion)
    SELECT
        id_producto,
        total_unidades,
        RANK() OVER (ORDER BY total_unidades DESC)
    FROM (
        SELECT p.id_producto, COALESCE(SUM(dv.cantidad), 0) AS total_unidades
        FROM productos p
        LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
        GROUP BY p.id_producto
    ) AS ventas_por_producto;
END$$

-- =====================================================================
-- 13. evt_backup_critical_tables_daily
-- Cada noche, realiza un respaldo lógico simplificado de las tablas
-- más importantes copiándolas a tablas *_backup.
-- NOTA: un backup real de producción debe hacerse con mysqldump u
-- otra herramienta externa; este evento es una simulación dentro del
-- alcance de un evento programado en SQL puro.
-- =====================================================================
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY)
DO
BEGIN
    TRUNCATE TABLE productos_backup;
    INSERT INTO productos_backup SELECT * FROM productos;

    TRUNCATE TABLE ventas_backup;
    INSERT INTO ventas_backup SELECT * FROM ventas;

    TRUNCATE TABLE clientes_backup;
    INSERT INTO clientes_backup SELECT * FROM clientes;
END$$

-- =====================================================================
-- 14. evt_clear_abandoned_carts_daily
-- Diariamente, cancela las ventas que llevan más de 72 horas en estado
-- 'Pendiente de Pago' (proxy de carrito abandonado, ver bloque 2).
-- =====================================================================
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
    UPDATE ventas
        SET estado = 'Cancelado'
        WHERE estado = 'Pendiente de Pago'
          AND fecha_venta < DATE_SUB(NOW(), INTERVAL 72 HOUR)$$

-- =====================================================================
-- 15. evt_calculate_monthly_kpis
-- Cada mes, calcula los KPIs principales del mes anterior.
-- =====================================================================
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 MONTH)
DO
BEGIN
    INSERT INTO kpis_mensuales (anio, mes, total_ventas, monto_total_vendido, clientes_nuevos)
    SELECT
        YEAR(CURDATE() - INTERVAL 1 MONTH),
        MONTH(CURDATE() - INTERVAL 1 MONTH),
        (SELECT COUNT(*) FROM ventas
            WHERE YEAR(fecha_venta) = YEAR(CURDATE() - INTERVAL 1 MONTH)
              AND MONTH(fecha_venta) = MONTH(CURDATE() - INTERVAL 1 MONTH)
              AND estado <> 'Cancelado'),
        (SELECT COALESCE(SUM(total), 0) FROM ventas
            WHERE YEAR(fecha_venta) = YEAR(CURDATE() - INTERVAL 1 MONTH)
              AND MONTH(fecha_venta) = MONTH(CURDATE() - INTERVAL 1 MONTH)
              AND estado <> 'Cancelado'),
        (SELECT COUNT(*) FROM clientes
            WHERE YEAR(fecha_registro) = YEAR(CURDATE() - INTERVAL 1 MONTH)
              AND MONTH(fecha_registro) = MONTH(CURDATE() - INTERVAL 1 MONTH));
END$$

-- =====================================================================
-- 16. evt_refresh_materialized_views_nightly
-- Cada noche, refresca la "vista materializada" simulada de resumen
-- por categoría (ver NOTA en la definición de mv_resumen_categorias).
-- =====================================================================
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 4 HOUR)
DO
BEGIN
    DELETE FROM mv_resumen_categorias;

    INSERT INTO mv_resumen_categorias (id_categoria, nombre_categoria, unidades_vendidas, ingresos_generados)
    SELECT
        cat.id_categoria,
        cat.nombre,
        COALESCE(SUM(dv.cantidad), 0),
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0)
    FROM categorias cat
    LEFT JOIN productos p ON p.id_categoria = cat.id_categoria
    LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    GROUP BY cat.id_categoria, cat.nombre;
END$$

-- =====================================================================
-- 17. evt_log_database_size_weekly
-- Semanalmente, registra el tamaño actual de la base de datos.
-- =====================================================================
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
    INSERT INTO tamano_bd_historico (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.TABLES
    WHERE table_schema = 'ecommerce_db'$$

-- =====================================================================
-- 18. evt_detect_fraudulent_activity_hourly
-- Cada hora, detecta clientes con más de 3 ventas canceladas en las
-- últimas 24 horas como patrón de actividad sospechosa.
-- =====================================================================
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP
DO
    INSERT INTO actividad_sospechosa (id_cliente, motivo)
    SELECT id_cliente, CONCAT('Más de 3 ventas canceladas en 24h: ', COUNT(*))
    FROM ventas
    WHERE estado = 'Cancelado'
      AND fecha_venta >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    GROUP BY id_cliente
    HAVING COUNT(*) > 3$$

-- =====================================================================
-- 19. evt_generate_supplier_performance_report_monthly
-- Cada mes, genera el reporte de rendimiento de proveedores del mes
-- anterior.
-- =====================================================================
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 MONTH)
DO
    INSERT INTO reporte_proveedores_mensual (id_proveedor, anio, mes, unidades_vendidas, ingresos_generados)
    SELECT
        prov.id_proveedor,
        YEAR(CURDATE() - INTERVAL 1 MONTH),
        MONTH(CURDATE() - INTERVAL 1 MONTH),
        COALESCE(SUM(dv.cantidad), 0),
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0)
    FROM proveedores prov
    LEFT JOIN productos p ON p.id_proveedor = prov.id_proveedor
    LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    LEFT JOIN ventas v ON v.id_venta = dv.id_venta
        AND YEAR(v.fecha_venta) = YEAR(CURDATE() - INTERVAL 1 MONTH)
        AND MONTH(v.fecha_venta) = MONTH(CURDATE() - INTERVAL 1 MONTH)
    GROUP BY prov.id_proveedor$$

-- =====================================================================
-- 20. evt_purge_soft_deleted_records_weekly
-- Semanalmente, elimina definitivamente los registros de
-- ventas_archivadas (nuestro equivalente de "borrado suave", ver
-- trigger trg_archive_deleted_venta) con más de 30 días archivados.
-- =====================================================================
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
    DELETE FROM ventas_archivadas
    WHERE fecha_archivado < DATE_SUB(NOW(), INTERVAL 30 DAY)$$

DELIMITER ;
