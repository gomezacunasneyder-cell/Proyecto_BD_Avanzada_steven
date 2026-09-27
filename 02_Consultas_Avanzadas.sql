USE ecommerce_db;

-- =====================================================================
-- 1. TOP 10 PRODUCTOS MÁS VENDIDOS
-- Pregunta de negocio: ¿cuáles son los 10 productos que más ingresos
-- han generado históricamente?
-- Lógica: se agrupa el detalle de ventas por producto, se multiplica
-- cantidad x precio congelado (no el precio actual) y se ordena
-- descendente por ese ingreso total.
-- =====================================================================
SELECT
    p.id_producto,
    p.nombre AS nombre_producto,
    SUM(dv.cantidad) AS total_unidades_vendidas,
    SUM(dv.cantidad * dv.precio_unitario_congelado) AS total_ingresos_generados
FROM detalle_ventas dv
INNER JOIN productos p ON p.id_producto = dv.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY total_ingresos_generados DESC
LIMIT 10;

-- =====================================================================
-- 2. PRODUCTOS CON BAJAS VENTAS
-- Pregunta de negocio: ¿qué productos están en el 10% inferior de
-- ingresos generados, y por tanto son candidatos a descontinuar?
-- Lógica: PERCENT_RANK() calcula la posición relativa (0 a 1) de cada
-- producto según sus ingresos; filtramos los que caen en el 10% más
-- bajo (percentil <= 0.10). Se incluyen productos sin ventas (LEFT JOIN)
-- porque un producto que nunca se ha vendido también es candidato.
-- =====================================================================
WITH ingresos_por_producto AS (
    SELECT
        p.id_producto,
        p.nombre AS nombre_producto,
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS total_ingresos
    FROM productos p
    LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    GROUP BY p.id_producto, p.nombre
),
productos_con_percentil AS (
    SELECT
        id_producto,
        nombre_producto,
        total_ingresos,
        PERCENT_RANK() OVER (ORDER BY total_ingresos) AS percentil_ingresos
    FROM ingresos_por_producto
)
SELECT id_producto, nombre_producto, total_ingresos, percentil_ingresos
FROM productos_con_percentil
WHERE percentil_ingresos <= 0.10
ORDER BY total_ingresos ASC;

-- =====================================================================
-- 3. CLIENTES VIP (TOP 5 POR LTV)
-- Pregunta de negocio: ¿cuáles son los 5 clientes con mayor valor de
-- vida (Lifetime Value), basado en gasto histórico real?
-- Lógica: se suman los totales de ventas NO canceladas por cliente.
-- Se excluyen las canceladas porque no representan ingreso real.
-- =====================================================================
SELECT
    c.id_cliente,
    fn_FormatearNombreCompleto(c.id_cliente) AS nombre_cliente,
    COUNT(v.id_venta) AS cantidad_compras_realizadas,
    SUM(v.total) AS valor_vida_cliente_ltv
FROM clientes c
INNER JOIN ventas v ON v.id_cliente = c.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.id_cliente
ORDER BY valor_vida_cliente_ltv DESC
LIMIT 5;

-- =====================================================================
-- 4. ANÁLISIS DE VENTAS MENSUALES
-- Pregunta de negocio: ¿cómo se comportan las ventas totales mes a mes?
-- Lógica: se agrupa por año y mes de la fecha de venta, sumando el
-- total de cada venta no cancelada. Sirve para ver estacionalidad.
-- =====================================================================
SELECT
    YEAR(fecha_venta) AS anio,
    MONTH(fecha_venta) AS mes_numero,
    MONTHNAME(fecha_venta) AS mes_nombre,
    COUNT(*) AS cantidad_ventas,
    SUM(total) AS monto_total_vendido
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY YEAR(fecha_venta), MONTH(fecha_venta), MONTHNAME(fecha_venta)
ORDER BY anio, mes_numero;

-- =====================================================================
-- 5. CRECIMIENTO DE CLIENTES POR TRIMESTRE
-- Pregunta de negocio: ¿cuántos clientes nuevos se registraron cada
-- trimestre? Mide la velocidad de adquisición de clientes.
-- Lógica: se agrupa la tabla clientes por año y trimestre de
-- fecha_registro, contando cuántos se dieron de alta en cada período.
-- =====================================================================
SELECT
    YEAR(fecha_registro) AS anio,
    QUARTER(fecha_registro) AS trimestre,
    COUNT(*) AS cantidad_clientes_nuevos
FROM clientes
GROUP BY YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY anio, trimestre;

-- =====================================================================
-- 6. TASA DE COMPRA REPETIDA
-- Pregunta de negocio: ¿qué porcentaje de los clientes ha comprado
-- más de una vez? Mide la fidelización de la base de clientes.
-- Lógica: subconsulta cuenta las compras por cliente; luego se
-- calcula qué fracción de esos clientes tiene más de 1 compra.
-- =====================================================================
SELECT
    ROUND(
        100.0 * SUM(CASE WHEN cantidad_compras > 1 THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS porcentaje_clientes_compra_repetida
FROM (
    SELECT id_cliente, COUNT(*) AS cantidad_compras
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
) AS resumen_compras_por_cliente;

-- =====================================================================
-- 7. PRODUCTOS COMPRADOS JUNTOS FRECUENTEMENTE
-- Pregunta de negocio: ¿qué pares de productos se compran juntos con
-- más frecuencia? Útil para estrategias de venta cruzada (cross-sell).
-- Lógica: self-join de detalle_ventas sobre la misma venta (mismo
-- id_venta), evitando duplicados y auto-pares con la condición
-- id_producto_a < id_producto_b.
-- =====================================================================
SELECT
    p1.nombre AS producto_a,
    p2.nombre AS producto_b,
    COUNT(*) AS veces_comprados_en_conjunto
FROM detalle_ventas dv1
INNER JOIN detalle_ventas dv2
    ON dv1.id_venta = dv2.id_venta
    AND dv1.id_producto < dv2.id_producto
INNER JOIN productos p1 ON p1.id_producto = dv1.id_producto
INNER JOIN productos p2 ON p2.id_producto = dv2.id_producto
GROUP BY p1.nombre, p2.nombre
ORDER BY veces_comprados_en_conjunto DESC
LIMIT 10;

-- =====================================================================
-- 8. ROTACIÓN DE INVENTARIO POR CATEGORÍA
-- Pregunta de negocio: ¿qué tan rápido se mueve el inventario de cada
-- categoría? Una rotación alta indica productos que se venden rápido.
-- Lógica: tasa_rotacion = unidades vendidas históricas / stock
-- promedio actual. NULLIF evita división por cero si el stock es 0.
-- =====================================================================
SELECT
    cat.id_categoria,
    cat.nombre AS nombre_categoria,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas_historicas,
    ROUND(AVG(p.stock), 2) AS stock_promedio_actual,
    ROUND(COALESCE(SUM(dv.cantidad), 0) / NULLIF(AVG(p.stock), 0), 2) AS tasa_rotacion_inventario
FROM categorias cat
INNER JOIN productos p ON p.id_categoria = cat.id_categoria
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY cat.id_categoria, cat.nombre
ORDER BY tasa_rotacion_inventario DESC;

-- =====================================================================
-- 9. PRODUCTOS QUE NECESITAN REABASTECIMIENTO
-- Pregunta de negocio: ¿qué productos están por debajo de su umbral
-- mínimo de stock y necesitan reorden urgente?
-- Lógica: comparación directa stock actual vs. umbral_minimo_stock,
-- solo para productos activos (no descontinuados).
-- =====================================================================
SELECT
    id_producto,
    nombre AS nombre_producto,
    stock AS stock_actual,
    umbral_minimo_stock,
    (umbral_minimo_stock - stock) AS unidades_faltantes_para_umbral
FROM productos
WHERE stock < umbral_minimo_stock
  AND activo = TRUE
ORDER BY unidades_faltantes_para_umbral DESC;

-- =====================================================================
-- 10. ANÁLISIS DE CARRITO ABANDONADO (SIMULADO)
-- Pregunta de negocio: ¿qué clientes iniciaron una compra pero no la
-- completaron en un período determinado?
-- NOTA METODOLÓGICA: el esquema del proyecto no define una entidad de
-- "carrito de compras" independiente. Como proxy se usan las ventas
-- que quedaron registradas en estado 'Pendiente de Pago' por más de
-- 24 horas sin avanzar a 'Procesando' u otro estado.
-- =====================================================================
SELECT
    v.id_venta,
    c.id_cliente,
    fn_FormatearNombreCompleto(c.id_cliente) AS nombre_cliente,
    v.fecha_venta AS fecha_inicio_compra,
    v.total AS monto_en_riesgo,
    TIMESTAMPDIFF(HOUR, v.fecha_venta, NOW()) AS horas_sin_completar_pago
FROM ventas v
INNER JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado = 'Pendiente de Pago'
  AND TIMESTAMPDIFF(HOUR, v.fecha_venta, NOW()) > 24
ORDER BY v.fecha_venta ASC;

-- =====================================================================
-- 11. RENDIMIENTO DE PROVEEDORES
-- Pregunta de negocio: ¿qué proveedores generan más ingresos a través
-- de los productos que suministran? Clasifica a los proveedores por
-- volumen e ingresos de ventas.
-- Lógica: se navega proveedor -> productos -> detalle_ventas, sumando
-- unidades e ingresos por proveedor.
-- =====================================================================
SELECT
    prov.id_proveedor,
    prov.nombre AS nombre_proveedor,
    COALESCE(SUM(dv.cantidad), 0) AS total_unidades_vendidas,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS total_ingresos_generados
FROM proveedores prov
LEFT JOIN productos p ON p.id_proveedor = prov.id_proveedor
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY prov.id_proveedor, prov.nombre
ORDER BY total_ingresos_generados DESC;

-- =====================================================================
-- 12. ANÁLISIS GEOGRÁFICO DE VENTAS
-- Pregunta de negocio: ¿en qué ciudades se concentran más las ventas?
-- Útil para decisiones de logística y marketing regional.
-- Lógica: se agrupan las ventas no canceladas por la ciudad del
-- cliente que las realizó.
-- =====================================================================
SELECT
    c.ciudad,
    COUNT(v.id_venta) AS cantidad_ventas,
    SUM(v.total) AS monto_total_vendido
FROM ventas v
INNER JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.ciudad
ORDER BY monto_total_vendido DESC;

-- =====================================================================
-- 13. VENTAS POR HORA DEL DÍA
-- Pregunta de negocio: ¿en qué horas del día se concentran más las
-- compras? Sirve para calendarizar campañas de marketing.
-- Lógica: se extrae la hora (0-23) de fecha_venta y se cuenta cuántas
-- ventas ocurrieron en cada franja horaria.
-- =====================================================================
SELECT
    HOUR(fecha_venta) AS hora_del_dia,
    COUNT(*) AS cantidad_ventas
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY HOUR(fecha_venta)
ORDER BY cantidad_ventas DESC;

-- =====================================================================
-- 14. IMPACTO DE PROMOCIONES
-- Pregunta de negocio: ¿cómo cambian las ventas de un producto antes y
-- después de un cambio de precio (usado como proxy de promoción)?
-- NOTA METODOLÓGICA: el esquema no define una entidad de "promoción"
-- independiente. Se usa la tabla log_cambios_precio (poblada por el
-- trigger de auditoría del bloque 5) para comparar unidades vendidas
-- en la semana previa y la semana posterior a cada cambio de precio.
-- =====================================================================
SELECT
    lcp.id_producto,
    p.nombre AS nombre_producto,
    lcp.fecha_cambio,
    lcp.precio_anterior,
    lcp.precio_nuevo,
    (SELECT COALESCE(SUM(dv.cantidad), 0)
       FROM detalle_ventas dv
       INNER JOIN ventas v ON v.id_venta = dv.id_venta
       WHERE dv.id_producto = lcp.id_producto
         AND v.fecha_venta BETWEEN DATE_SUB(lcp.fecha_cambio, INTERVAL 7 DAY) AND lcp.fecha_cambio
    ) AS unidades_vendidas_semana_antes,
    (SELECT COALESCE(SUM(dv.cantidad), 0)
       FROM detalle_ventas dv
       INNER JOIN ventas v ON v.id_venta = dv.id_venta
       WHERE dv.id_producto = lcp.id_producto
         AND v.fecha_venta BETWEEN lcp.fecha_cambio AND DATE_ADD(lcp.fecha_cambio, INTERVAL 7 DAY)
    ) AS unidades_vendidas_semana_despues
FROM log_cambios_precio lcp
INNER JOIN productos p ON p.id_producto = lcp.id_producto
ORDER BY lcp.fecha_cambio DESC;

-- =====================================================================
-- 15. ANÁLISIS DE COHORT
-- Pregunta de negocio: ¿los clientes que empezaron a comprar en un mes
-- determinado (su "cohorte") siguen comprando en los meses siguientes?
-- Mide retención real de clientes en el tiempo.
-- Lógica: primera_compra identifica el mes de la PRIMERA compra de
-- cada cliente (su cohorte). compras_mensuales lista en qué meses
-- volvió a comprar. PERIOD_DIFF calcula cuántos meses han pasado
-- desde el mes de cohorte hasta cada mes de actividad.
-- =====================================================================
WITH primera_compra AS (
    SELECT id_cliente, MIN(DATE_FORMAT(fecha_venta, '%Y-%m-01')) AS mes_cohorte
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
),
compras_mensuales AS (
    SELECT
        v.id_cliente,
        DATE_FORMAT(v.fecha_venta, '%Y-%m-01') AS mes_de_actividad
    FROM ventas v
    WHERE v.estado <> 'Cancelado'
    GROUP BY v.id_cliente, DATE_FORMAT(v.fecha_venta, '%Y-%m-01')
)
SELECT
    pc.mes_cohorte,
    PERIOD_DIFF(DATE_FORMAT(cm.mes_de_actividad, '%Y%m'), DATE_FORMAT(pc.mes_cohorte, '%Y%m')) AS meses_desde_cohorte,
    COUNT(DISTINCT cm.id_cliente) AS clientes_activos_en_ese_mes
FROM primera_compra pc
INNER JOIN compras_mensuales cm ON cm.id_cliente = pc.id_cliente
GROUP BY pc.mes_cohorte, meses_desde_cohorte
ORDER BY pc.mes_cohorte, meses_desde_cohorte;

-- =====================================================================
-- 16. MARGEN DE BENEFICIO POR PRODUCTO
-- Pregunta de negocio: ¿qué margen de ganancia deja cada producto,
-- tanto en valor absoluto como en porcentaje?
-- Lógica: margen_absoluto = precio - costo. margen_porcentual expresa
-- ese margen como % del precio de venta.
-- =====================================================================
SELECT
    id_producto,
    nombre AS nombre_producto,
    precio AS precio_venta,
    costo AS costo_adquisicion,
    (precio - costo) AS margen_absoluto,
    ROUND(100.0 * (precio - costo) / precio, 2) AS margen_porcentual
FROM productos
ORDER BY margen_porcentual DESC;

-- =====================================================================
-- 17. TIEMPO PROMEDIO ENTRE COMPRAS
-- Pregunta de negocio: ¿cada cuántos días, en promedio, vuelve a
-- comprar un mismo cliente? Sirve para calendarizar campañas de
-- retención.
-- Lógica: LAG() trae la fecha de la compra INMEDIATAMENTE anterior
-- del mismo cliente; DATEDIFF calcula los días entre ambas; luego se
-- promedia por cliente.
-- =====================================================================
WITH compras_con_fecha_anterior AS (
    SELECT
        id_cliente,
        fecha_venta,
        LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS fecha_compra_anterior
    FROM ventas
    WHERE estado <> 'Cancelado'
)
SELECT
    id_cliente,
    ROUND(AVG(DATEDIFF(fecha_venta, fecha_compra_anterior)), 1) AS promedio_dias_entre_compras
FROM compras_con_fecha_anterior
WHERE fecha_compra_anterior IS NOT NULL
GROUP BY id_cliente
ORDER BY promedio_dias_entre_compras ASC;

-- =====================================================================
-- 18. PRODUCTOS MÁS VISTOS VS. COMPRADOS
-- Pregunta de negocio: ¿qué productos generan más interés (vistas) en
-- comparación con lo que realmente se compra?
-- NOTA METODOLÓGICA: el esquema no incluye una tabla de tracking de
-- visualizaciones de producto (no está contemplada en la sección de
-- entidades del enunciado). Para implementar esta consulta con datos
-- reales se necesitaría una tabla adicional, por ejemplo:
--   vistas_producto(id_vista, id_producto, id_cliente, fecha_vista)
-- Como alternativa dentro del alcance actual, se muestra el ranking
-- de productos más COMPRADOS, que puede servir de base de comparación
-- una vez se agregue el tracking de vistas.
-- =====================================================================
SELECT
    p.id_producto,
    p.nombre AS nombre_producto,
    COALESCE(SUM(dv.cantidad), 0) AS total_unidades_compradas
FROM productos p
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY total_unidades_compradas DESC;

-- =====================================================================
-- 19. SEGMENTACIÓN DE CLIENTES (RFM)
-- Pregunta de negocio: ¿cómo se segmentan los clientes según Recencia
-- (hace cuánto compraron), Frecuencia (cuántas veces) y Monetario
-- (cuánto han gastado)?
-- Lógica: rfm_base calcula las 3 métricas crudas por cliente. NTILE(4)
-- divide a los clientes en 4 grupos (cuartiles) para cada métrica;
-- un score_recencia alto = compró más recientemente (mejor).
-- =====================================================================
WITH rfm_base AS (
    SELECT
        c.id_cliente,
        fn_FormatearNombreCompleto(c.id_cliente) AS nombre_cliente,
        DATEDIFF(NOW(), MAX(v.fecha_venta)) AS dias_desde_ultima_compra,
        COUNT(v.id_venta) AS cantidad_compras,
        SUM(v.total) AS monto_total_gastado
    FROM clientes c
    INNER JOIN ventas v ON v.id_cliente = c.id_cliente
    WHERE v.estado <> 'Cancelado'
    GROUP BY c.id_cliente
)
SELECT
    id_cliente,
    nombre_cliente,
    dias_desde_ultima_compra,
    cantidad_compras,
    monto_total_gastado,
    NTILE(4) OVER (ORDER BY dias_desde_ultima_compra DESC) AS score_recencia,
    NTILE(4) OVER (ORDER BY cantidad_compras ASC) AS score_frecuencia,
    NTILE(4) OVER (ORDER BY monto_total_gastado ASC) AS score_monetario
FROM rfm_base
ORDER BY monto_total_gastado DESC;

-- =====================================================================
-- 20. PREDICCIÓN DE DEMANDA SIMPLE
-- Pregunta de negocio: ¿cuántas unidades se espera vender el próximo
-- mes para cada categoría, basado en el histórico?
-- Lógica: se calcula el promedio de unidades vendidas por mes en cada
-- categoría (promedio móvil simple), usado como proyección ingenua
-- del próximo mes.
-- =====================================================================
WITH ventas_mensuales_por_categoria AS (
    SELECT
        cat.id_categoria,
        cat.nombre AS nombre_categoria,
        DATE_FORMAT(v.fecha_venta, '%Y-%m') AS anio_mes,
        SUM(dv.cantidad) AS unidades_vendidas_en_el_mes
    FROM detalle_ventas dv
    INNER JOIN ventas v ON v.id_venta = dv.id_venta
    INNER JOIN productos p ON p.id_producto = dv.id_producto
    INNER JOIN categorias cat ON cat.id_categoria = p.id_categoria
    WHERE v.estado <> 'Cancelado'
    GROUP BY cat.id_categoria, cat.nombre, DATE_FORMAT(v.fecha_venta, '%Y-%m')
)
SELECT
    id_categoria,
    nombre_categoria,
    ROUND(AVG(unidades_vendidas_en_el_mes), 1) AS proyeccion_unidades_proximo_mes
FROM ventas_mensuales_por_categoria
GROUP BY id_categoria, nombre_categoria
ORDER BY proyeccion_unidades_proximo_mes DESC;
