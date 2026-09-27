# Proyecto de Base de Datos para un E-commerce

## Descripción Breve
Este proyecto tiene como objetivo diseñar e implementar la arquitectura central de una base de datos relacional para una plataforma de comercio electrónico de alto rendimiento. El sistema gestiona de manera robusta, eficiente y segura el catálogo de productos, la trazabilidad de proveedores, el control de inventarios, el ciclo de vida de los clientes y la integridad de las transacciones comerciales. Además, integra técnicas avanzadas de base de datos como consultas analíticas complejas, funciones personalizadas (UDFs), automatización de tareas en tiempo real mediante el programador de eventos de MySQL, auditoría forense con disparadores (triggers), lógica de negocio encapsulada en procedimientos almacenados con garantías ACID y un modelo de seguridad basado en roles (**RBAC**).

---

## Integrantes
* **Senyder Steven Gómez Acuña**

---

## 📌 Arquitectura y Entidades Principales

El diseño del esquema relacional fue normalizado en **Tercera Forma Normal (3NF)** para eliminar redundancias y proteger la integridad de la información a través de restricciones de clave foránea (`FOREIGN KEY`) y chequeos de validación (`CHECK`):

1. **`categorias`**: Organización jerárquica del catálogo de productos.
2. **`proveedores`**: Gestión de la cadena de suministro y datos de contacto comercial.
3. **`productos`**: Almacena el inventario público e interno con códigos SKU únicos, restricciones para evitar costos/precios negativos (`precio > 0`, `costo >= 0`) e indicadores de disponibilidad.
4. **`clientes`**: Registro de usuarios con almacenamiento seguro de contraseñas, correos únicos y direcciones de despacho.
5. **`ventas`**: Encabezado global de las órdenes de compra que controla las fechas y estados del pedido (`'Pendiente de Pago'`, `'Procesando'`, `'Enviado'`, `'Entregado'`, `'Cancelado'`).
6. **`detalle_ventas`**: Tabla puente M:N entre ventas y productos.
   > **Integridad Histórica (Requisito Crítico):** Implementa el campo `precio_unitario_congelado` para conservar el valor del producto al momento exacto de la compra. Si el precio cambia en el catálogo futuro, el registro contable de la venta histórica se mantiene intacto.

---

## 🚀 Instrucciones de Ejecución

Para desplegar y reconstruir la base de datos de manera correcta, los archivos SQL deben ejecutarse en el siguiente **orden secuencial estricto** utilizando un cliente de MySQL (CLI, MySQL Workbench o DBeaver) con privilegios de usuario administrador (`root`):

```bash
# Comandos de ejecución secuencial en consola (CLI):
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p < 02_Consultas_Avanzadas.sql
mysql -u root -p < 03_Funciones.sql
mysql -u root -p < 04_Seguridad.sql
mysql -u root -p < 05_Triggers.sql
mysql -u root -p < 06_Eventos.sql
mysql -u root -p < 07_Procedimientos_Almacenados.sql
