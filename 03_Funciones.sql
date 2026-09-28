USE ecommerce_db;

ALTER TABLE productos
    ADD COLUMN peso_kg DECIMAL(6,3) NOT NULL DEFAULT 0.500 AFTER stock;

UPDATE productos SET peso_kg = 0.300 WHERE sku = 'SKU-ELEC-001';
UPDATE productos SET peso_kg = 0.150 WHERE sku = 'SKU-ELEC-002';
UPDATE productos SET peso_kg = 0.200 WHERE sku = 'SKU-ELEC-003';
UPDATE productos SET peso_kg = 1.200 WHERE sku = 'SKU-ELEC-004';
UPDATE productos SET peso_kg = 0.120 WHERE sku = 'SKU-ELEC-005';
UPDATE productos SET peso_kg = 0.250 WHERE sku = 'SKU-ROPA-001';
UPDATE productos SET peso_kg = 0.600 WHERE sku = 'SKU-ROPA-002';
UPDATE productos SET peso_kg = 0.900 WHERE sku = 'SKU-ROPA-003';
UPDATE productos SET peso_kg = 0.500 WHERE sku = 'SKU-ROPA-004';
UPDATE productos SET peso_kg = 1.800 WHERE sku = 'SKU-HOGAR-001';
UPDATE productos SET peso_kg = 1.100 WHERE sku = 'SKU-HOGAR-002';
UPDATE productos SET peso_kg = 4.500 WHERE sku = 'SKU-HOGAR-003';
UPDATE productos SET peso_kg = 0.450 WHERE sku = 'SKU-DEP-001';
UPDATE productos SET peso_kg = 6.000 WHERE sku = 'SKU-DEP-002';
UPDATE productos SET peso_kg = 1.000 WHERE sku = 'SKU-DEP-003';
UPDATE productos SET peso_kg = 0.350 WHERE sku = 'SKU-LIB-001';
UPDATE productos SET peso_kg = 0.400 WHERE sku = 'SKU-LIB-002';
UPDATE productos SET peso_kg = 0.300 WHERE sku = 'SKU-LIB-003';
UPDATE productos SET peso_kg = 0.280 WHERE sku = 'SKU-ELEC-006';
UPDATE productos SET peso_kg = 0.400 WHERE sku = 'SKU-HOGAR-004';

DELIMITER $$

CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
        INTO v_total
        FROM detalle_ventas
        WHERE id_venta = p_id_venta;
    RETURN v_total;
END$$

CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN FALSE;
    END IF;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    IF v_stock IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN v_stock >= p_cantidad;
END$$

CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
    RETURN v_precio;
END$$

CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha_nac DATE;
    DECLARE v_edad INT;
    SELECT fecha_nacimiento INTO v_fecha_nac FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_fecha_nac IS NULL THEN
        RETURN NULL;
    END IF;
    SET v_edad = TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());
    RETURN v_edad;
END$$

CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(210)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre VARCHAR(100);
    DECLARE v_apellido VARCHAR(100);
    SELECT nombre, apellido INTO v_nombre, v_apellido
        FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_nombre IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN CONCAT(v_nombre, ' ', v_apellido);
END$$

CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra
        FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN DATEDIFF(NOW(), v_primera_compra) <= 30;
END$$

CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(10,3);
    DECLARE v_costo_base DECIMAL(10,2) DEFAULT 8000;
    DECLARE v_costo_por_kg DECIMAL(10,2) DEFAULT 3500;

    SELECT COALESCE(SUM(dv.cantidad * p.peso_kg), 0) INTO v_peso_total
        FROM detalle_ventas dv
        INNER JOIN productos p ON p.id_producto = dv.id_producto
        WHERE dv.id_venta = p_id_venta;

    IF v_peso_total = 0 THEN
        RETURN 0;
    END IF;

    RETURN v_costo_base + (v_peso_total * v_costo_por_kg);
END$$

CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(12,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_porcentaje < 0 OR p_porcentaje > 100 THEN
        RETURN p_monto;
    END IF;
    RETURN ROUND(p_monto - (p_monto * p_porcentaje / 100), 2);
END$$

CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima DATETIME;
    SELECT MAX(fecha_venta) INTO v_ultima
        FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_ultima;
END$$

CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    IF p_email IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END$$

CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre_categoria VARCHAR(100);
    SELECT c.nombre INTO v_nombre_categoria
        FROM productos p
        INNER JOIN categorias c ON c.id_categoria = p.id_categoria
        WHERE p.id_producto = p_id_producto;
    RETURN v_nombre_categoria;
END$$

CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total
        FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_total;
END$$

CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima DATETIME;
    SELECT MAX(fecha_venta) INTO v_ultima
        FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_ultima IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(NOW(), v_ultima);
END$$

CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(10)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_gastado DECIMAL(12,2);
    SELECT total_gastado INTO v_total_gastado
        FROM clientes WHERE id_cliente = p_id_cliente;

    IF v_total_gastado IS NULL THEN
        RETURN 'Bronce';
    ELSEIF v_total_gastado >= 500000 THEN
        RETURN 'Oro';
    ELSEIF v_total_gastado >= 200000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END$$

CREATE FUNCTION fn_GenerarSKU(p_nombre_producto VARCHAR(150), p_id_categoria INT)
RETURNS VARCHAR(50)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_prefijo_categoria VARCHAR(10);
    DECLARE v_prefijo_nombre VARCHAR(10);
    DECLARE v_sufijo VARCHAR(9);
    DECLARE v_sku VARCHAR(50);
    DECLARE v_sku_existente INT DEFAULT 1;

    SELECT UPPER(LEFT(REPLACE(nombre, ' ', ''), 4)) INTO v_prefijo_categoria
        FROM categorias WHERE id_categoria = p_id_categoria;

    IF v_prefijo_categoria IS NULL THEN
        SET v_prefijo_categoria = 'GEN';
    END IF;

    SET v_prefijo_nombre = UPPER(LEFT(REPLACE(COALESCE(p_nombre_producto, 'GEN'), ' ', ''), 4));

    WHILE v_sku_existente > 0 DO
        SET v_sufijo = LPAD(FLOOR(RAND() * 1000000000), 9, '0');
        SET v_sku = CONCAT('SKU-', v_prefijo_categoria, '-', v_prefijo_nombre, '-', v_sufijo);
        SELECT COUNT(*) INTO v_sku_existente
            FROM productos
            WHERE sku = v_sku;
    END WHILE;

    RETURN v_sku;
END$$

CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_tarifa_iva DECIMAL(5,4) DEFAULT 0.19;
    IF p_monto IS NULL OR p_monto < 0 THEN
        RETURN 0;
    END IF;
    RETURN ROUND(p_monto * v_tarifa_iva, 2);
END$$

CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock_total INT;
    SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
        FROM productos
        WHERE id_categoria = p_id_categoria AND activo = TRUE;
    RETURN v_stock_total;
END$$

CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_dias_entrega INT DEFAULT 5;

    SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;

    IF v_ciudad IN ('Bogotá', 'Medellín', 'Cali') THEN
        SET v_dias_entrega = 2;
    ELSEIF v_ciudad IN ('Barranquilla', 'Bucaramanga', 'Cúcuta') THEN
        SET v_dias_entrega = 4;
    ELSE
        SET v_dias_entrega = 7;
    END IF;

    RETURN DATE_ADD(CURDATE(), INTERVAL v_dias_entrega DAY);
END$$

CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(12,2), p_tasa_cambio DECIMAL(10,4))
RETURNS DECIMAL(14,4)
DETERMINISTIC
NO SQL
BEGIN
    IF p_monto IS NULL OR p_tasa_cambio IS NULL OR p_tasa_cambio <= 0 THEN
        RETURN NULL;
    END IF;
    RETURN ROUND(p_monto * p_tasa_cambio, 4);
END$$

CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    IF p_contrasena IS NULL OR LENGTH(p_contrasena) < 12 THEN
        RETURN FALSE;
    END IF;
    IF p_contrasena NOT REGEXP '[A-Z]' THEN
        RETURN FALSE;
    END IF;
    IF p_contrasena NOT REGEXP '[a-z]' THEN
        RETURN FALSE;
    END IF;
    IF p_contrasena NOT REGEXP '[0-9]' THEN
        RETURN FALSE;
    END IF;
    IF p_contrasena NOT REGEXP '[^A-Za-z0-9]' THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END$$

DELIMITER ;
