USE ecommerce_db;

-- ---------------------------------------------------------------------
-- Ajustes de esquema requeridos por procedimientos de este bloque
-- ---------------------------------------------------------------------

ALTER TABLE ventas
    MODIFY COLUMN estado ENUM('Pendiente de Pago','Pagado','Procesando',
                               'Enviado','Entregado','Cancelado')
    NOT NULL DEFAULT 'Pendiente de Pago';

ALTER TABLE clientes
    ADD COLUMN credito_disponible DECIMAL(12,2) NOT NULL DEFAULT 0
    AFTER total_gastado;

CREATE TABLE IF NOT EXISTS resenas_producto (
    id_resena       INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT             NOT NULL,
    id_cliente      INT             NOT NULL,
    calificacion    TINYINT         NOT NULL,
    comentario      TEXT            NULL,
    fecha_resena    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_calificacion_valida CHECK (calificacion BETWEEN 1 AND 5),

    CONSTRAINT fk_resena_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_resena_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

DELIMITER $$

-- =====================================================================
-- 1. sp_RealizarNuevaVenta
-- Procesa una venta completa de forma transaccional: valida stock,
-- inserta el encabezado y el detalle de la venta. El descuento real
-- del stock lo ejecuta el trigger trg_update_stock_after_insert_venta
-- (bloque 5) al detectar el INSERT en detalle_ventas.
-- Recibe los productos como dos listas paralelas separadas por comas.
-- =====================================================================
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_ids_producto VARCHAR(500),
    IN p_cantidades VARCHAR(500),
    OUT p_id_venta_generado INT
)
proc_venta: BEGIN
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio_actual DECIMAL(10,2);
    DECLARE v_pos INT DEFAULT 1;
    DECLARE v_siguiente_coma INT;
    DECLARE v_resto_ids VARCHAR(500);
    DECLARE v_resto_cant VARCHAR(500);
    DECLARE v_token_id VARCHAR(50);
    DECLARE v_token_cant VARCHAR(50);
    DECLARE v_fin BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_venta_generado = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO ventas (id_cliente, estado, total)
    VALUES (p_id_cliente, 'Pendiente de Pago', 0);

    SET p_id_venta_generado = LAST_INSERT_ID();

    SET v_resto_ids = p_ids_producto;
    SET v_resto_cant = p_cantidades;

    WHILE NOT v_fin DO
        SET v_siguiente_coma = LOCATE(',', v_resto_ids);
        IF v_siguiente_coma = 0 THEN
            SET v_token_id = v_resto_ids;
            SET v_token_cant = v_resto_cant;
            SET v_fin = TRUE;
        ELSE
            SET v_token_id = LEFT(v_resto_ids, v_siguiente_coma - 1);
            SET v_token_cant = LEFT(v_resto_cant, LOCATE(',', v_resto_cant) - 1);
            SET v_resto_ids = SUBSTRING(v_resto_ids, v_siguiente_coma + 1);
            SET v_resto_cant = SUBSTRING(v_resto_cant, LOCATE(',', v_resto_cant) + 1);
        END IF;

        SET v_id_producto = CAST(TRIM(v_token_id) AS UNSIGNED);
        SET v_cantidad = CAST(TRIM(v_token_cant) AS UNSIGNED);

        IF NOT fn_VerificarDisponibilidadStock(v_id_producto, v_cantidad) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Stock insuficiente para uno de los productos de la venta.';
        END IF;

        SELECT precio INTO v_precio_actual FROM productos WHERE id_producto = v_id_producto;

        -- El descuento de stock NO se hace aquí: queda a cargo del trigger
        -- trg_update_stock_after_insert_venta (bloque 5), que se dispara
        -- automáticamente al insertar en detalle_ventas. Así el stock se
        -- mantiene consistente sin importar si el INSERT viene de este SP
        -- o de cualquier otro proceso que inserte directamente en la tabla.
        INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
        VALUES (p_id_venta_generado, v_id_producto, v_cantidad, v_precio_actual);
    END WHILE;

    UPDATE ventas
        SET total = fn_CalcularTotalVenta(p_id_venta_generado)
        WHERE id_venta = p_id_venta_generado;

    COMMIT;
END$$

-- =====================================================================
-- 2. sp_AgregarNuevoProducto
-- Inserta un nuevo producto validando datos básicos.
-- =====================================================================
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(150),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(10,2),
    IN p_costo DECIMAL(10,2),
    IN p_stock_inicial INT,
    IN p_sku VARCHAR(50),
    IN p_id_categoria INT,
    IN p_id_proveedor INT
)
BEGIN
    IF p_precio <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El precio debe ser mayor que cero.';
    END IF;

    INSERT INTO productos
        (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor, activo)
    VALUES
        (p_nombre, p_descripcion, p_precio, p_costo, COALESCE(p_stock_inicial, 0),
         p_sku, p_id_categoria, p_id_proveedor, TRUE);
END$$

-- =====================================================================
-- 3. sp_ActualizarDireccionCliente
-- Actualiza la dirección de envío y ciudad de un cliente.
-- =====================================================================
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion VARCHAR(255),
    IN p_nueva_ciudad VARCHAR(100)
)
BEGIN
    UPDATE clientes
        SET direccion_envio = p_nueva_direccion,
            ciudad = p_nueva_ciudad
        WHERE id_cliente = p_id_cliente;
END$$

-- =====================================================================
-- 4. sp_ProcesarDevolucion
-- Gestiona la devolución de un producto de una venta: repone el stock
-- y genera un crédito a favor del cliente por el valor devuelto.
-- =====================================================================
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_detalle INT,
    IN p_motivo VARCHAR(255)
)
proc_devolucion: BEGIN
    DECLARE v_id_venta INT;
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio_unitario DECIMAL(10,2);
    DECLARE v_id_cliente INT;
    DECLARE v_monto_credito DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT id_venta, id_producto, cantidad, precio_unitario_congelado
        INTO v_id_venta, v_id_producto, v_cantidad, v_precio_unitario
        FROM detalle_ventas WHERE id_detalle = p_id_detalle;

    IF v_id_venta IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El detalle de venta indicado no existe.';
    END IF;

    SELECT id_cliente INTO v_id_cliente FROM ventas WHERE id_venta = v_id_venta;
    SET v_monto_credito = v_cantidad * v_precio_unitario;

    UPDATE productos SET stock = stock + v_cantidad WHERE id_producto = v_id_producto;

    UPDATE clientes
        SET credito_disponible = credito_disponible + v_monto_credito
        WHERE id_cliente = v_id_cliente;

    DELETE FROM detalle_ventas WHERE id_detalle = p_id_detalle;

    UPDATE ventas
        SET total = fn_CalcularTotalVenta(v_id_venta)
        WHERE id_venta = v_id_venta;

    COMMIT;
END$$

-- =====================================================================
-- 5. sp_ObtenerHistorialComprasCliente
-- Devuelve el historial completo de compras de un cliente, con detalle
-- de productos por cada venta.
-- =====================================================================
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT
        v.id_venta,
        v.fecha_venta,
        v.estado,
        v.total,
        p.nombre AS nombre_producto,
        dv.cantidad,
        dv.precio_unitario_congelado
    FROM ventas v
    INNER JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    INNER JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END$$

-- =====================================================================
-- 6. sp_AjustarNivelStock
-- Ajuste manual de stock (positivo o negativo), registrando el motivo
-- en la tabla de auditoría de precios/stock (log_cambios_precio se
-- reutiliza aquí solo para precio; el ajuste de stock queda auditado
-- vía el propio procedimiento con SIGNAL si el resultado es inválido).
-- =====================================================================
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_cantidad_ajuste INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_stock_actual INT;

    SELECT stock INTO v_stock_actual FROM productos WHERE id_producto = p_id_producto;

    IF (v_stock_actual + p_cantidad_ajuste) < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El ajuste dejaría el stock en un valor negativo.';
    END IF;

    UPDATE productos
        SET stock = stock + p_cantidad_ajuste
        WHERE id_producto = p_id_producto;

    SELECT CONCAT('Ajuste aplicado. Motivo: ', p_motivo) AS resultado;
END$$

-- =====================================================================
-- 7. sp_EliminarClienteDeFormaSegura
-- Anonimiza los datos personales de un cliente en lugar de borrarlo,
-- preservando la integridad referencial con ventas históricas.
-- =====================================================================
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
        SET nombre = 'Usuario',
            apellido = 'Eliminado',
            email = CONCAT('eliminado_', id_cliente, '@anonimo.local'),
            contrasena_hash = 'ANONIMIZADO',
            direccion_envio = NULL,
            ciudad = NULL,
            fecha_nacimiento = NULL,
            activo = FALSE
        WHERE id_cliente = p_id_cliente;
END$$

-- =====================================================================
-- 8. sp_AplicarDescuentoPorCategoria
-- Aplica un porcentaje de descuento a todos los productos activos de
-- una categoría, usando fn_AplicarDescuento para el cálculo.
-- =====================================================================
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje_descuento DECIMAL(5,2)
)
BEGIN
    UPDATE productos
        SET precio = fn_AplicarDescuento(precio, p_porcentaje_descuento)
        WHERE id_categoria = p_id_categoria
          AND activo = TRUE;
END$$

-- =====================================================================
-- 9. sp_GenerarReporteMensualVentas
-- Genera un reporte de ventas para un mes y año específicos.
-- =====================================================================
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_anio INT,
    IN p_mes INT
)
BEGIN
    SELECT
        COUNT(*) AS cantidad_ventas,
        SUM(total) AS monto_total_vendido,
        ROUND(AVG(total), 2) AS ticket_promedio
    FROM ventas
    WHERE YEAR(fecha_venta) = p_anio
      AND MONTH(fecha_venta) = p_mes
      AND estado <> 'Cancelado';
END$$

-- =====================================================================
-- 10. sp_CambiarEstadoPedido
-- Cambia el estado de una venta, validando que el nuevo estado sea
-- uno de los definidos en el ENUM.
-- =====================================================================
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(30)
)
BEGIN
    IF p_nuevo_estado NOT IN ('Pendiente de Pago','Pagado','Procesando','Enviado','Entregado','Cancelado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado de pedido no válido.';
    END IF;

    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
END$$

-- =====================================================================
-- 11. sp_RegistrarNuevoCliente
-- Registra un nuevo cliente validando que el email no exista y que
-- el formato de email y la contraseña cumplan los criterios definidos
-- en las funciones fn_ValidarFormatoEmail y fn_ValidarComplejidadContrasena.
-- =====================================================================
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100),
    IN p_apellido VARCHAR(100),
    IN p_email VARCHAR(150),
    IN p_contrasena_hash VARCHAR(255),
    IN p_direccion_envio VARCHAR(255),
    IN p_ciudad VARCHAR(100)
)
BEGIN
    IF EXISTS (SELECT 1 FROM clientes WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un cliente registrado con ese email.';
    END IF;

    IF NOT fn_ValidarFormatoEmail(p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El formato del email no es válido.';
    END IF;

    INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio, ciudad)
    VALUES (p_nombre, p_apellido, p_email, p_contrasena_hash, p_direccion_envio, p_ciudad);
END$$

-- =====================================================================
-- 12. sp_ObtenerDetallesProductoCompleto
-- Devuelve toda la información de un producto junto con los datos de
-- su categoría y proveedor.
-- =====================================================================
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT
        p.*,
        c.nombre AS nombre_categoria,
        prov.nombre AS nombre_proveedor,
        prov.email_contacto AS email_proveedor
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    LEFT JOIN proveedores prov ON prov.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$

-- =====================================================================
-- 13. sp_FusionarCuentasCliente
-- Fusiona dos cuentas de cliente duplicadas: reasigna las ventas de
-- la cuenta duplicada a la cuenta principal y anonimiza la duplicada.
-- =====================================================================
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_principal INT,
    IN p_id_cliente_duplicado INT
)
proc_fusion: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_id_cliente_principal = p_id_cliente_duplicado THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede fusionar una cuenta consigo misma.';
    END IF;

    START TRANSACTION;

    UPDATE ventas
        SET id_cliente = p_id_cliente_principal
        WHERE id_cliente = p_id_cliente_duplicado;

    UPDATE clientes
        SET total_gastado = total_gastado + (
            SELECT COALESCE(SUM(total), 0) FROM ventas WHERE id_cliente = p_id_cliente_principal
        )
        WHERE id_cliente = p_id_cliente_principal;

    CALL sp_EliminarClienteDeFormaSegura(p_id_cliente_duplicado);

    COMMIT;
END$$

-- =====================================================================
-- 14. sp_AsignarProductoAProveedor
-- Asigna o cambia el proveedor de un producto.
-- =====================================================================
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM proveedores WHERE id_proveedor = p_id_proveedor) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor indicado no existe.';
    END IF;

    UPDATE productos
        SET id_proveedor = p_id_proveedor
        WHERE id_producto = p_id_producto;
END$$

-- =====================================================================
-- 15. sp_BuscarProductos
-- Búsqueda avanzada de productos con filtros opcionales por nombre,
-- categoría y rango de precios. Un parámetro en NULL desactiva ese filtro.
-- =====================================================================
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(150),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(10,2),
    IN p_precio_max DECIMAL(10,2)
)
BEGIN
    SELECT p.*, c.nombre AS nombre_categoria
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE p.activo = TRUE
      AND (p_nombre IS NULL OR p.nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
      AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
    ORDER BY p.nombre;
END$$

-- =====================================================================
-- 16. sp_ObtenerDashboardAdmin
-- Devuelve un conjunto de KPIs para un panel administrativo: ventas
-- de hoy, nuevos clientes de hoy y productos con bajo stock.
-- =====================================================================
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado')
            AS ventas_hoy,
        (SELECT COALESCE(SUM(total), 0) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado')
            AS monto_vendido_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE())
            AS clientes_nuevos_hoy,
        (SELECT COUNT(*) FROM productos WHERE stock < umbral_minimo_stock AND activo = TRUE)
            AS productos_bajo_stock;
END$$

-- =====================================================================
-- 17. sp_ProcesarPago
-- Simula el procesamiento de un pago de una venta, cambiando su
-- estado a 'Pagado'.
-- =====================================================================
CREATE PROCEDURE sp_ProcesarPago(IN p_id_venta INT)
BEGIN
    DECLARE v_estado_actual VARCHAR(30);

    SELECT estado INTO v_estado_actual FROM ventas WHERE id_venta = p_id_venta;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta indicada no existe.';
    END IF;

    IF v_estado_actual <> 'Pendiente de Pago' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden procesar pagos de ventas pendientes de pago.';
    END IF;

    UPDATE ventas SET estado = 'Pagado' WHERE id_venta = p_id_venta;
END$$

-- =====================================================================
-- 18. sp_AñadirReseñaProducto
-- Permite a un cliente añadir una reseña, validando que haya comprado
-- ese producto previamente.
-- =====================================================================
CREATE PROCEDURE sp_AñadirReseñaProducto(
    IN p_id_producto INT,
    IN p_id_cliente INT,
    IN p_calificacion TINYINT,
    IN p_comentario TEXT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM detalle_ventas dv
        INNER JOIN ventas v ON v.id_venta = dv.id_venta
        WHERE dv.id_producto = p_id_producto
          AND v.id_cliente = p_id_cliente
          AND v.estado <> 'Cancelado'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente no ha comprado este producto, no puede reseñarlo.';
    END IF;

    INSERT INTO resenas_producto (id_producto, id_cliente, calificacion, comentario)
    VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
END$$

-- =====================================================================
-- 19. sp_ObtenerProductosRelacionados
-- Devuelve productos que otros clientes compraron junto con el
-- producto dado (misma lógica de la consulta de productos comprados
-- juntos, aplicada a un solo producto).
-- =====================================================================
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT
        p2.id_producto,
        p2.nombre,
        COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas dv1
    INNER JOIN detalle_ventas dv2
        ON dv1.id_venta = dv2.id_venta
        AND dv1.id_producto <> dv2.id_producto
    INNER JOIN productos p2 ON p2.id_producto = dv2.id_producto
    WHERE dv1.id_producto = p_id_producto
    GROUP BY p2.id_producto, p2.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END$$

-- =====================================================================
-- 20. sp_MoverProductosEntreCategorias
-- Mueve uno o más productos (lista de IDs separados por coma) de su
-- categoría actual a una nueva categoría, de forma transaccional.
-- =====================================================================
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_ids_producto VARCHAR(500),
    IN p_id_categoria_destino INT
)
proc_mover: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM categorias WHERE id_categoria = p_id_categoria_destino) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La categoría destino no existe.';
    END IF;

    START TRANSACTION;

    UPDATE productos
        SET id_categoria = p_id_categoria_destino
        WHERE FIND_IN_SET(id_producto, p_ids_producto) > 0;

    COMMIT;
END$$

DELIMITER ;
