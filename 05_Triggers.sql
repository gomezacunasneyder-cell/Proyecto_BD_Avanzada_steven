USE ecommerce_db;

-- ---------------------------------------------------------------------
-- Tablas auxiliares requeridas por los triggers de este bloque
-- (log_cambios_precio ya fue creada en 01_Esquema_y_Datos.sql)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS auditoria_clientes (
    id_auditoria    INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente      INT NOT NULL,
    accion          VARCHAR(50) NOT NULL,
    fecha_evento    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS auditoria_estado_pedido (
    id_auditoria    INT AUTO_INCREMENT PRIMARY KEY,
    id_venta        INT NOT NULL,
    estado_anterior VARCHAR(30) NOT NULL,
    estado_nuevo    VARCHAR(30) NOT NULL,
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS alertas_stock (
    id_alerta       INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT NOT NULL,
    stock_al_momento INT NOT NULL,
    fecha_alerta    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS ventas_archivadas (
    id_venta_original  INT NOT NULL,
    id_cliente         INT NOT NULL,
    fecha_venta        DATETIME NOT NULL,
    estado             VARCHAR(30) NOT NULL,
    total               DECIMAL(12,2) NOT NULL,
    fecha_archivado     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_venta_original)
) ENGINE = InnoDB;

-- Tabla que simula el catálogo de permisos asignados (MySQL no permite
-- crear triggers directamente sobre sentencias GRANT/REVOKE, que son
-- DCL). Para cumplir el requisito de auditar cambios de permisos, los
-- cambios se registran en esta tabla intermedia y el trigger reacciona
-- sobre ella.
CREATE TABLE IF NOT EXISTS permisos_usuarios (
    id_permiso      INT AUTO_INCREMENT PRIMARY KEY,
    usuario         VARCHAR(100) NOT NULL,
    rol_asignado    VARCHAR(100) NOT NULL,
    fecha_asignacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS auditoria_permisos (
    id_auditoria    INT AUTO_INCREMENT PRIMARY KEY,
    usuario         VARCHAR(100) NOT NULL,
    rol_asignado    VARCHAR(100) NOT NULL,
    accion          VARCHAR(20) NOT NULL,
    fecha_evento    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

ALTER TABLE clientes
    ADD COLUMN id_referido INT NULL AFTER credito_disponible;

ALTER TABLE categorias
    ADD COLUMN contador_productos INT NOT NULL DEFAULT 0;

-- Sincroniza el contador con los datos actuales antes de que el
-- trigger #20 empiece a mantenerlo hacia adelante.
UPDATE categorias c
SET contador_productos = (
    SELECT COUNT(*) FROM productos p WHERE p.id_categoria = c.id_categoria
);

-- Asegura que exista una categoría "General" para el trigger #19.
INSERT INTO categorias (nombre, descripcion)
SELECT 'General', 'Categoría por defecto para productos sin clasificar'
WHERE NOT EXISTS (SELECT 1 FROM categorias WHERE nombre = 'General');

DELIMITER $$

-- =====================================================================
-- 1. trg_audit_precio_producto_after_update
-- Evento elegido: AFTER UPDATE en productos.
-- Guarda un registro en log_cambios_precio solo cuando el precio
-- realmente cambió (no en cada UPDATE de cualquier otra columna).
-- =====================================================================
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <> OLD.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio);
    END IF;
END$$

-- =====================================================================
-- 2. trg_check_stock_before_insert_venta
-- Evento elegido: BEFORE INSERT en detalle_ventas (aquí es donde se
-- conoce el producto y la cantidad de la venta).
-- Impide insertar una línea de venta si no hay stock suficiente.
-- =====================================================================
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_disponible INT;

    SELECT stock INTO v_stock_disponible
        FROM productos WHERE id_producto = NEW.id_producto;

    IF v_stock_disponible IS NULL OR v_stock_disponible < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock insuficiente para completar esta línea de venta.';
    END IF;
END$$

-- =====================================================================
-- 3. trg_update_stock_after_insert_venta
-- Evento elegido: AFTER INSERT en detalle_ventas.
-- Descuenta el stock del producto vendido. Esta es la ÚNICA fuente de
-- verdad para el descuento de stock (sp_RealizarNuevaVenta ya NO lo
-- hace manualmente, ver Fase 4).
-- =====================================================================
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
        SET stock = stock - NEW.cantidad
        WHERE id_producto = NEW.id_producto;
END$$

-- =====================================================================
-- 4. trg_prevent_delete_categoria_with_products
-- Evento elegido: BEFORE DELETE en categorias.
-- Impide eliminar una categoría si todavía tiene productos asociados.
-- =====================================================================
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM productos WHERE id_categoria = OLD.id_categoria) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar una categoría que aún tiene productos asociados.';
    END IF;
END$$

-- =====================================================================
-- 5. trg_log_new_customer_after_insert
-- Evento elegido: AFTER INSERT en clientes.
-- Registra en auditoria_clientes cada alta de cliente nuevo.
-- =====================================================================
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_clientes (id_cliente, accion)
    VALUES (NEW.id_cliente, 'ALTA_CLIENTE');
END$$

-- =====================================================================
-- 6. trg_update_total_gastado_cliente
-- Evento elegido: AFTER UPDATE en ventas.
-- Cuando el total de una venta cambia (ej. al recalcularse tras el
-- detalle, o al procesarse el pago), se ajusta total_gastado del
-- cliente por la diferencia, evitando duplicar sumas.
-- =====================================================================
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.total <> OLD.total AND NEW.estado <> 'Cancelado' THEN
        UPDATE clientes
            SET total_gastado = total_gastado + (NEW.total - OLD.total)
            WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$

-- =====================================================================
-- 7. trg_set_fecha_modificacion_producto
-- Evento elegido: BEFORE UPDATE en productos.
-- Actualiza fecha_modificacion de forma explícita vía trigger (la
-- columna también tiene ON UPDATE CURRENT_TIMESTAMP como respaldo).
-- =====================================================================
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END$$

-- =====================================================================
-- 8. trg_prevent_negative_stock
-- Evento elegido: BEFORE UPDATE en productos.
-- Última línea de defensa: impide guardar un stock negativo aunque
-- la lógica de aplicación falle. Complementa el CHECK de la tabla.
-- =====================================================================
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El stock de un producto no puede quedar en un valor negativo.';
    END IF;
END$$

-- =====================================================================
-- 9. trg_capitalize_nombre_cliente
-- Evento elegido: BEFORE INSERT en clientes.
-- Normaliza nombre y apellido a formato "Primera Letra Mayúscula".
-- =====================================================================
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre, 1)), LOWER(SUBSTRING(NEW.nombre, 2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END$$

-- =====================================================================
-- 10. trg_recalculate_total_venta_on_detalle_change
-- Evento elegido: AFTER INSERT en detalle_ventas.
-- Recalcula el total de la venta usando fn_CalcularTotalVenta cada vez
-- que se agrega una línea nueva. (Para cubrir UPDATE/DELETE del
-- detalle también se requeriría un trigger equivalente por cada
-- evento; se documenta como alcance de este trigger).
-- =====================================================================
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
        SET total = fn_CalcularTotalVenta(NEW.id_venta)
        WHERE id_venta = NEW.id_venta;
END$$

-- =====================================================================
-- 11. trg_log_order_status_change
-- Evento elegido: AFTER UPDATE en ventas.
-- Audita cada cambio de estado de un pedido.
-- =====================================================================
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> OLD.estado THEN
        INSERT INTO auditoria_estado_pedido (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END$$

-- =====================================================================
-- 12. trg_prevent_price_zero_or_less
-- Evento elegido: BEFORE UPDATE en productos.
-- Refuerza a nivel de trigger la regla de que el precio no puede
-- quedar en cero o negativo (ya existe el CHECK chk_precio_positivo
-- para el caso de INSERT).
-- =====================================================================
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El precio de un producto no puede ser cero o negativo.';
    END IF;
END$$

-- =====================================================================
-- 13. trg_send_stock_alert_on_low_stock
-- Evento elegido: AFTER UPDATE en productos.
-- Inserta una alerta cuando el stock cae por debajo del umbral mínimo
-- (y no estaba ya por debajo antes del UPDATE, para no duplicar alertas).
-- =====================================================================
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < NEW.umbral_minimo_stock AND OLD.stock >= OLD.umbral_minimo_stock THEN
        INSERT INTO alertas_stock (id_producto, stock_al_momento)
        VALUES (NEW.id_producto, NEW.stock);
    END IF;
END$$

-- =====================================================================
-- 14. trg_archive_deleted_venta
-- Evento elegido: BEFORE DELETE en ventas.
-- Mueve la venta a ventas_archivadas antes de que se borre físicamente.
-- =====================================================================
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta_original, id_cliente, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total);
END$$

-- =====================================================================
-- 15. trg_validate_email_format_on_customer
-- Evento elegido: BEFORE INSERT en clientes.
-- Usa fn_ValidarFormatoEmail para rechazar emails mal formados antes
-- de insertarlos.
-- =====================================================================
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El formato del email del cliente no es válido.';
    END IF;
END$$

-- =====================================================================
-- 16. trg_update_last_order_date_customer
-- Evento elegido: AFTER INSERT en ventas.
-- Actualiza fecha_ultima_compra del cliente al registrar una venta nueva.
-- =====================================================================
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
        SET fecha_ultima_compra = NEW.fecha_venta
        WHERE id_cliente = NEW.id_cliente;
END$$

-- =====================================================================
-- 17. trg_prevent_self_referral
-- Evento elegido: BEFORE UPDATE en clientes.
-- Impide que un cliente quede referenciado a sí mismo en el programa
-- de referidos (columna id_referido agregada en este bloque).
-- =====================================================================
CREATE TRIGGER trg_prevent_self_referral
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NEW.id_referido = NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Un cliente no puede referirse a sí mismo.';
    END IF;
END$$

-- =====================================================================
-- 18. trg_log_permission_changes
-- Evento elegido: AFTER INSERT en permisos_usuarios.
-- NOTA METODOLÓGICA: MySQL no permite crear triggers directamente
-- sobre sentencias GRANT/REVOKE (son DCL, no DML). Como workaround,
-- cada asignación de rol se registra en permisos_usuarios y este
-- trigger audita ese registro. El bloque 04_Seguridad.sql inserta en
-- permisos_usuarios al asignar cada rol.
-- =====================================================================
CREATE TRIGGER trg_log_permission_changes
AFTER INSERT ON permisos_usuarios
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_permisos (usuario, rol_asignado, accion)
    VALUES (NEW.usuario, NEW.rol_asignado, 'ASIGNACION');
END$$

-- =====================================================================
-- 19. trg_assign_default_category_on_null
-- Evento elegido: BEFORE INSERT en productos.
-- Si el producto se inserta sin categoría, se le asigna la categoría
-- "General" (creada al inicio de este script si no existía).
-- =====================================================================
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    DECLARE v_id_general INT;

    IF NEW.id_categoria IS NULL THEN
        SELECT id_categoria INTO v_id_general
            FROM categorias WHERE nombre = 'General' LIMIT 1;
        SET NEW.id_categoria = v_id_general;
    END IF;
END$$

-- =====================================================================
-- 20. trg_update_producto_count_in_categoria
-- Evento elegido: AFTER INSERT en productos.
-- Mantiene contador_productos de la categoría actualizado al insertar
-- un producto nuevo. (El caso de UPDATE de categoría o DELETE de
-- producto requeriría triggers equivalentes adicionales).
-- =====================================================================
CREATE TRIGGER trg_update_producto_count_in_categoria
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias
        SET contador_productos = contador_productos + 1
        WHERE id_categoria = NEW.id_categoria;
END$$

DELIMITER ;
