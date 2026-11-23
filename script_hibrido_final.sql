-- ============================================================================
-- PROYECTO: Red Social Estudiantil Pascualina - Arquitectura Hibrida
-- MOTOR: PostgreSQL (Relacional + JSONB + Flujo IoT)
-- ============================================================================

-- 1. TABLAS RELACIONALES Y SEMIESTRUCTURADAS (JSONB)

CREATE TABLE usuarios (
    usuario_id SERIAL PRIMARY KEY,
    nombre_completo VARCHAR(120) NOT NULL,
    correo VARCHAR(150) UNIQUE NOT NULL,
    programa_academico VARCHAR(100) NOT NULL,
    -- Preferencias flexibles del usuario sin alterar el esquema fijo
    preferencias JSONB NOT NULL DEFAULT '{}'::jsonb,
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE publicaciones (
    publicacion_id SERIAL PRIMARY KEY,
    usuario_id INT NOT NULL REFERENCES usuarios(usuario_id) ON DELETE CASCADE,
    tipo_contenido VARCHAR(30) NOT NULL, -- texto, imagen, video, enlace, evento
    cuerpo TEXT NOT NULL,
    -- Atributos variables segun el formato (resolucion, duracion, tamano_mb, etc.)
    metadatos_media JSONB NOT NULL DEFAULT '{}'::jsonb,
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE interacciones (
    interaccion_id SERIAL PRIMARY KEY,
    publicacion_id INT NOT NULL REFERENCES publicaciones(publicacion_id) ON DELETE CASCADE,
    usuario_id INT NOT NULL REFERENCES usuarios(usuario_id) ON DELETE CASCADE,
    tipo_interaccion VARCHAR(25) NOT NULL, -- reaccion, comentario, compartido
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE espacios_campus (
    espacio_id SERIAL PRIMARY KEY,
    nombre_espacio VARCHAR(100) NOT NULL,
    bloque_o_sede VARCHAR(80) NOT NULL,
    capacidad_maxima INT NOT NULL CHECK (capacidad_maxima > 0)
);

CREATE TABLE dispositivos_iot (
    dispositivo_id SERIAL PRIMARY KEY,
    espacio_id INT NOT NULL REFERENCES espacios_campus(espacio_id) ON DELETE CASCADE,
    tipo_sensor VARCHAR(50) NOT NULL, -- ocupacion, asistencia, ambiente
    estado VARCHAR(20) NOT NULL DEFAULT 'activo',
    -- Parametros de calibracion y muestreo propios de cada sensor
    config_sensor JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Tabla de alto volumen (append-only) para lecturas continuas de sensores
CREATE TABLE lecturas_iot (
    lectura_id BIGSERIAL PRIMARY KEY,
    dispositivo_id INT NOT NULL REFERENCES dispositivos_iot(dispositivo_id) ON DELETE CASCADE,
    espacio_id INT NOT NULL REFERENCES espacios_campus(espacio_id) ON DELETE CASCADE,
    -- Mediciones o eventos enviados por el dispositivo
    payload_lectura JSONB NOT NULL,
    registrado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. INDICES PARA OPTIMIZACION DE CONSULTAS Y BIG DATA

-- Indice GIN para buscar claves y valores dentro de metadatos multimedia
CREATE INDEX idx_publicaciones_metadatos_gin ON publicaciones USING GIN (metadatos_media);

-- Indice GIN para consultas sobre lecturas semiestructuradas de sensores
CREATE INDEX idx_lecturas_iot_payload_gin ON lecturas_iot USING GIN (payload_lectura);

-- Indice compuesto para consultas frecuentes por espacio y rango de tiempo
CREATE INDEX idx_lecturas_iot_espacio_fecha ON lecturas_iot (espacio_id, registrado_en DESC);

-- 3. DATOS DE PRUEBA (DML - INSERT)

INSERT INTO usuarios (nombre_completo, correo, programa_academico, preferencias) VALUES
('Mariana Rivera', 'mariana.rivera@pascualbravo.edu.co', 'Tecnologia en Desarrollo de Software', '{"tema": "oscuro", "notificaciones_push": true}'::jsonb),
('Carlos Gomez', 'carlos.gomez@pascualbravo.edu.co', 'Ingenieria de Sistemas', '{"tema": "claro", "notificaciones_push": false}'::jsonb);

INSERT INTO espacios_campus (nombre_espacio, bloque_o_sede, capacidad_maxima) VALUES
('Aula 302', 'Bloque B', 35),
('Biblioteca Central - Zona Estudio', 'Sede Principal', 80);

INSERT INTO dispositivos_iot (espacio_id, tipo_sensor, estado, config_sensor) VALUES
(1, 'ocupacion', 'activo', '{"frecuencia_seg": 60, "umbral_alerta": 32}'::jsonb),
(2, 'ocupacion', 'activo', '{"frecuencia_seg": 120, "umbral_alerta": 75}'::jsonb);

INSERT INTO publicaciones (usuario_id, tipo_contenido, cuerpo, metadatos_media) VALUES
(1, 'video', 'Repaso de estructuras de datos y grafos', '{"formato": "mp4", "resolucion": "1080p", "tamano_mb": 48.5}'::jsonb),
(2, 'imagen', 'Apuntes de bases de datos hibridas', '{"formato": "png", "resolucion": "1200x800", "tamano_mb": 3.2}'::jsonb);

INSERT INTO interacciones (publicacion_id, usuario_id, tipo_interaccion) VALUES
(1, 2, 'reaccion'),
(1, 2, 'comentario'),
(2, 1, 'reaccion');

INSERT INTO lecturas_iot (dispositivo_id, espacio_id, payload_lectura, registrado_en) VALUES
(1, 1, '{"ocupacion_actual": 34, "alerta": true}'::jsonb, NOW() - INTERVAL '2 hours'),
(1, 1, '{"ocupacion_actual": 22, "alerta": false}'::jsonb, NOW() - INTERVAL '1 hour'),
(2, 2, '{"ocupacion_actual": 54, "alerta": false}'::jsonb, NOW() - INTERVAL '30 minutes');

-- 4. CONSULTAS ANALITICAS (DML - SELECT CON JOIN, AGREGACIONES Y JSONB)

-- Consulta A: Publicaciones, interacciones y peso multimedia por programa academico
SELECT
    u.programa_academico,
    COUNT(DISTINCT p.publicacion_id) AS total_publicaciones,
    COUNT(i.interaccion_id) AS total_interacciones,
    COALESCE(SUM((p.metadatos_media->>'tamano_mb')::NUMERIC), 0) AS mb_multimedia_total
FROM usuarios u
LEFT JOIN publicaciones p ON p.usuario_id = u.usuario_id
LEFT JOIN interacciones i ON i.publicacion_id = p.publicacion_id
GROUP BY u.programa_academico
ORDER BY total_interacciones DESC;

-- Consulta B: Ocupacion promedio y alertas IoT por espacio del campus
SELECT
    e.nombre_espacio,
    e.capacidad_maxima,
    d.tipo_sensor,
    COUNT(l.lectura_id) AS total_lecturas,
    ROUND(AVG((l.payload_lectura->>'ocupacion_actual')::NUMERIC), 1) AS promedio_ocupacion,
    SUM(CASE WHEN COALESCE((l.payload_lectura->>'alerta')::BOOLEAN, FALSE) THEN 1 ELSE 0 END) AS total_alertas
FROM lecturas_iot l
JOIN espacios_campus e ON e.espacio_id = l.espacio_id
JOIN dispositivos_iot d ON d.dispositivo_id = l.dispositivo_id
WHERE l.payload_lectura ? 'ocupacion_actual'
GROUP BY e.espacio_id, e.nombre_espacio, e.capacidad_maxima, d.tipo_sensor
ORDER BY promedio_ocupacion DESC;

-- Consulta C: Publicaciones en formato mp4 filtradas con operador JSONB @>
SELECT
    p.publicacion_id,
    u.nombre_completo,
    p.metadatos_media->>'formato' AS formato,
    p.metadatos_media->>'resolucion' AS resolucion,
    COUNT(i.interaccion_id) AS total_interacciones
FROM publicaciones p
JOIN usuarios u ON u.usuario_id = p.usuario_id
LEFT JOIN interacciones i ON i.publicacion_id = p.publicacion_id
WHERE p.metadatos_media @> '{"formato": "mp4"}'::jsonb
GROUP BY p.publicacion_id, u.nombre_completo, p.metadatos_media
ORDER BY total_interacciones DESC;