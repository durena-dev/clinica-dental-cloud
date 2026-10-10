-- Sistema web para consultorios dentales - Modelo de datos (PostgreSQL 15+)
-- Ejecutar con un usuario que pueda crear extensiones (Supabase lo permite).

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------- Seguridad ----------
CREATE TABLE roles (
  id_role      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name         varchar(30)  NOT NULL UNIQUE,
  description  varchar(200)
);

CREATE TABLE users (
  id_user        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_role        smallint     NOT NULL REFERENCES roles (id_role) ON DELETE RESTRICT,
  full_name      varchar(150) NOT NULL,
  email          varchar(255) NOT NULL UNIQUE,
  phone          varchar(30),
  password_hash  varchar(255) NOT NULL,
  status         varchar(10)  NOT NULL DEFAULT 'ACTIVE'
                 CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at     timestamptz  NOT NULL DEFAULT now(),
  updated_at     timestamptz  NOT NULL DEFAULT now()
);

-- ---------- Pacientes ----------
CREATE TABLE patients (
  id_patient         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_user            bigint UNIQUE REFERENCES users (id_user) ON DELETE RESTRICT,
  full_name          varchar(150) NOT NULL,
  identification     varchar(30)  NOT NULL UNIQUE,
  birth_date         date,
  phone              varchar(30),
  email              varchar(255),
  emergency_contact  varchar(200),
  data_consent_at    timestamptz,
  status             varchar(10)  NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at         timestamptz  NOT NULL DEFAULT now(),
  updated_at         timestamptz  NOT NULL DEFAULT now()
);

-- ---------- Odontologos y servicios ----------
CREATE TABLE specialties (
  id_specialty  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name          varchar(100) NOT NULL UNIQUE,
  description   varchar(300)
);

CREATE TABLE dentists (
  id_dentist      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_user         bigint      NOT NULL UNIQUE REFERENCES users (id_user) ON DELETE RESTRICT,
  id_specialty    smallint    NOT NULL REFERENCES specialties (id_specialty) ON DELETE RESTRICT,
  license_number  varchar(30) NOT NULL UNIQUE,
  status          varchar(10) NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE services (
  id_service        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name              varchar(120)  NOT NULL UNIQUE,
  description       varchar(500),
  duration_minutes  smallint      NOT NULL CHECK (duration_minutes > 0),
  price             numeric(10,2) NOT NULL CHECK (price >= 0),
  status            varchar(10)   NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at        timestamptz   NOT NULL DEFAULT now(),
  updated_at        timestamptz   NOT NULL DEFAULT now()
);

CREATE TABLE dentist_services (
  id_dentist  bigint NOT NULL REFERENCES dentists (id_dentist) ON DELETE RESTRICT,
  id_service  bigint NOT NULL REFERENCES services (id_service) ON DELETE RESTRICT,
  PRIMARY KEY (id_dentist, id_service)
);

-- Horario semanal habitual (day_of_week: 1 = lunes ... 7 = domingo)
CREATE TABLE dentist_schedules (
  id_schedule  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_dentist   bigint   NOT NULL REFERENCES dentists (id_dentist) ON DELETE CASCADE,
  day_of_week  smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
  start_time   time     NOT NULL,
  end_time     time     NOT NULL,
  CHECK (end_time > start_time),
  UNIQUE (id_dentist, day_of_week, start_time)
);

-- Bloqueos puntuales (vacaciones, reuniones, permisos)
CREATE TABLE dentist_blocks (
  id_block    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_dentist  bigint      NOT NULL REFERENCES dentists (id_dentist) ON DELETE CASCADE,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  reason      varchar(255),
  CHECK (ends_at > starts_at)
);

-- ---------- Citas ----------
CREATE TABLE appointments (
  id_appointment  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_patient      bigint        NOT NULL REFERENCES patients (id_patient) ON DELETE RESTRICT,
  id_dentist      bigint        NOT NULL,
  id_service      bigint        NOT NULL,
  starts_at       timestamptz   NOT NULL,
  ends_at         timestamptz   NOT NULL,
  status          varchar(15)   NOT NULL DEFAULT 'PENDING'
                  CHECK (status IN ('PENDING', 'CONFIRMED', 'COMPLETED', 'CANCELLED', 'NO_SHOW')),
  price_snapshot  numeric(10,2) NOT NULL CHECK (price_snapshot >= 0),
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  -- La cita solo puede usar un servicio que ese odontologo tenga habilitado
  FOREIGN KEY (id_dentist, id_service)
    REFERENCES dentist_services (id_dentist, id_service) ON DELETE RESTRICT,
  -- Un odontologo no puede tener dos citas activas que se traslapen
  CONSTRAINT appointments_no_overlap
    EXCLUDE USING gist (id_dentist WITH =, tstzrange(starts_at, ends_at) WITH &&)
    WHERE (status <> 'CANCELLED')
);

CREATE TABLE appointment_logs (
  id_log           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_appointment   bigint      NOT NULL REFERENCES appointments (id_appointment) ON DELETE RESTRICT,
  changed_by       bigint      NOT NULL REFERENCES users (id_user) ON DELETE RESTRICT,
  previous_status  varchar(15),
  new_status       varchar(15) NOT NULL,
  changed_at       timestamptz NOT NULL DEFAULT now(),
  remarks          varchar(500)
);

CREATE TABLE medical_records (
  id_record       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_appointment  bigint      NOT NULL UNIQUE REFERENCES appointments (id_appointment) ON DELETE RESTRICT,
  symptoms        text,
  physical_exam   text,
  diagnosis       text,
  treatment_plan  text,
  prescriptions   text,
  clinical_notes  text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id_notification  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_appointment   bigint       NOT NULL REFERENCES appointments (id_appointment) ON DELETE RESTRICT,
  type             varchar(20)  NOT NULL CHECK (type IN ('CONFIRMATION', 'REMINDER', 'CANCELLATION')),
  channel          varchar(10)  NOT NULL DEFAULT 'EMAIL' CHECK (channel IN ('EMAIL')),
  recipient        varchar(255) NOT NULL,
  status           varchar(10)  NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
  retry_count      smallint     NOT NULL DEFAULT 0,
  scheduled_for    timestamptz  NOT NULL,
  sent_at          timestamptz,
  created_at       timestamptz  NOT NULL DEFAULT now()
);

-- ---------- Indices de apoyo ----------
CREATE INDEX idx_appointments_dentist_start ON appointments (id_dentist, starts_at);
CREATE INDEX idx_appointments_patient_start ON appointments (id_patient, starts_at);
CREATE INDEX idx_appointment_logs_appointment ON appointment_logs (id_appointment);
CREATE INDEX idx_notifications_pending ON notifications (scheduled_for) WHERE status = 'PENDING';
