USE ecommerce_db;

CREATE TABLE IF NOT EXISTS Auditoria_Clientes (
    id_auditoria        INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente          INT          NOT NULL,
    campo_modificado    VARCHAR(50)  NOT NULL,
    valor_antiguo       VARCHAR(255) NULL,
    valor_nuevo         VARCHAR(255) NULL,
    fecha_modificacion  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_auditoria_campo
        CHECK (campo_modificado IN ('email', 'direccion_envio')),

    INDEX idx_auditoria_cliente_fecha (id_cliente, fecha_modificacion),

    CONSTRAINT fk_auditoria_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

DROP TRIGGER IF EXISTS trg_audit_cliente_after_update;

DELIMITER $$

CREATE TRIGGER trg_audit_cliente_after_update
AFTER UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NOT (OLD.email <=> NEW.email) THEN
        INSERT INTO Auditoria_Clientes
            (id_cliente, campo_modificado, valor_antiguo, valor_nuevo)
        VALUES
            (OLD.id_cliente, 'email', OLD.email, NEW.email);
    END IF;

    IF NOT (OLD.direccion_envio <=> NEW.direccion_envio) THEN
        INSERT INTO Auditoria_Clientes
            (id_cliente, campo_modificado, valor_antiguo, valor_nuevo)
        VALUES
            (OLD.id_cliente, 'direccion_envio', OLD.direccion_envio, NEW.direccion_envio);
    END IF;
END$$

DELIMITER ;
