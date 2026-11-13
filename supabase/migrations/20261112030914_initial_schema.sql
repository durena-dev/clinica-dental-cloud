-- Dental clinic data model (PostgreSQL 15+)

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

-- ---------- Users and roles ----------
CREATE TABLE roles (
  id_role      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name         varchar(30)  NOT NULL UNIQUE,
  description  varchar(200)
);

CREATE TABLE users (
  id_user        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_role        smallint     NOT NULL REFERENCES roles (id_role) ON DELETE RESTRICT,
  full_name      varchar(150) NOT NULL,
  email          varchar(255) NOT NULL CONSTRAINT users_email_key UNIQUE,
  phone          varchar(30),
  password_hash  varchar(255) NOT NULL,
  status         varchar(10)  NOT NULL DEFAULT 'ACTIVE'
                 CONSTRAINT users_status_check CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at     timestamptz  NOT NULL DEFAULT now(),
  updated_at     timestamptz  NOT NULL DEFAULT now()
);

-- ---------- Patients ----------
CREATE TABLE patients (
  id_patient         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_user            bigint CONSTRAINT patients_id_user_key UNIQUE REFERENCES users (id_user) ON DELETE RESTRICT,
  full_name          varchar(150) NOT NULL,
  identification     varchar(30)  NOT NULL CONSTRAINT patients_identification_key UNIQUE,
  birth_date         date,
  phone              varchar(30),
  email              varchar(255),
  emergency_contact  varchar(200),
  data_consent_at    timestamptz,
  status             varchar(10)  NOT NULL DEFAULT 'ACTIVE'
                     CONSTRAINT patients_status_check CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at         timestamptz  NOT NULL DEFAULT now(),
  updated_at         timestamptz  NOT NULL DEFAULT now()
);

-- ---------- Dentists and services ----------
CREATE TABLE specialties (
  id_specialty  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name          varchar(100) NOT NULL UNIQUE,
  description   varchar(300)
);

CREATE TABLE dentists (
  id_dentist      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_user         bigint      NOT NULL CONSTRAINT dentists_id_user_key UNIQUE REFERENCES users (id_user) ON DELETE RESTRICT,
  id_specialty    smallint    NOT NULL REFERENCES specialties (id_specialty) ON DELETE RESTRICT,
  license_number  varchar(30) NOT NULL CONSTRAINT dentists_license_number_key UNIQUE,
  status          varchar(10) NOT NULL DEFAULT 'ACTIVE'
                  CONSTRAINT dentists_status_check CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE services (
  id_service        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name              varchar(120)  NOT NULL UNIQUE,
  description       varchar(500),
  duration_minutes  smallint      NOT NULL CONSTRAINT services_duration_minutes_check CHECK (duration_minutes > 0),
  price             numeric(10,2) NOT NULL CONSTRAINT services_price_check CHECK (price >= 0),
  status            varchar(10)   NOT NULL DEFAULT 'ACTIVE'
                    CONSTRAINT services_status_check CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at        timestamptz   NOT NULL DEFAULT now(),
  updated_at        timestamptz   NOT NULL DEFAULT now()
);

CREATE TABLE dentist_services (
  id_dentist  bigint NOT NULL REFERENCES dentists (id_dentist) ON DELETE RESTRICT,
  id_service  bigint NOT NULL REFERENCES services (id_service) ON DELETE RESTRICT,
  PRIMARY KEY (id_dentist, id_service)
);

-- day_of_week: 1 = Monday ... 7 = Sunday (ISO); times are clinic local time
CREATE TABLE dentist_schedules (
  id_schedule  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_dentist   bigint   NOT NULL REFERENCES dentists (id_dentist) ON DELETE CASCADE,
  day_of_week  smallint NOT NULL CONSTRAINT dentist_schedules_day_of_week_check CHECK (day_of_week BETWEEN 1 AND 7),
  start_time   time     NOT NULL,
  end_time     time     NOT NULL,
  CONSTRAINT dentist_schedules_time_range_check CHECK (end_time > start_time),
  CONSTRAINT dentist_schedules_slot_unique UNIQUE (id_dentist, day_of_week, start_time)
);

CREATE TABLE dentist_blocks (
  id_block    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_dentist  bigint      NOT NULL REFERENCES dentists (id_dentist) ON DELETE CASCADE,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  reason      varchar(255),
  CONSTRAINT dentist_blocks_time_range_check CHECK (ends_at > starts_at),
  -- tstzrange is [start, end): a block ending at 10:00 does not collide with one starting at 10:00
  CONSTRAINT dentist_blocks_no_overlap
    EXCLUDE USING gist (id_dentist WITH =, tstzrange(starts_at, ends_at) WITH &&)
);

-- ---------- Appointments ----------
CREATE TABLE appointments (
  id_appointment  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_patient      bigint        NOT NULL REFERENCES patients (id_patient) ON DELETE RESTRICT,
  id_dentist      bigint        NOT NULL,
  id_service      bigint        NOT NULL,
  starts_at       timestamptz   NOT NULL,
  ends_at         timestamptz   NOT NULL,
  status          varchar(15)   NOT NULL DEFAULT 'PENDING'
                  CONSTRAINT appointments_status_check CHECK (status IN ('PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'NO_SHOW')),
  price_snapshot  numeric(10,2) NOT NULL CONSTRAINT appointments_price_snapshot_check CHECK (price_snapshot >= 0),
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT appointments_time_range_check CHECK (ends_at > starts_at),
  -- Composite FK: the appointment can only use a service the dentist is enabled for
  CONSTRAINT appointments_dentist_service_fkey
    FOREIGN KEY (id_dentist, id_service)
    REFERENCES dentist_services (id_dentist, id_service) ON DELETE RESTRICT,
  -- Cancelled appointments free the slot; the range is [start, end), so back-to-back appointments are allowed
  CONSTRAINT appointments_no_overlap
    EXCLUDE USING gist (id_dentist WITH =, tstzrange(starts_at, ends_at) WITH &&)
    WHERE (status <> 'CANCELLED')
);

-- previous_status is NULL on the creation log entry
CREATE TABLE appointment_logs (
  id_log           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_appointment   bigint      NOT NULL REFERENCES appointments (id_appointment) ON DELETE RESTRICT,
  changed_by       bigint      NOT NULL REFERENCES users (id_user) ON DELETE RESTRICT,
  previous_status  varchar(15)
                   CONSTRAINT appointment_logs_previous_status_check CHECK (previous_status IN ('PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'NO_SHOW')),
  new_status       varchar(15) NOT NULL
                   CONSTRAINT appointment_logs_new_status_check CHECK (new_status IN ('PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'NO_SHOW')),
  changed_at       timestamptz NOT NULL DEFAULT now(),
  remarks          varchar(500)
);

CREATE TABLE medical_records (
  id_record       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_appointment  bigint      NOT NULL CONSTRAINT medical_records_id_appointment_key UNIQUE REFERENCES appointments (id_appointment) ON DELETE RESTRICT,
  symptoms        text,
  physical_exam   text        NOT NULL,
  diagnosis       text        NOT NULL,
  treatment_plan  text        NOT NULL,
  prescriptions   text,
  clinical_notes  text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id_notification  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_appointment   bigint       NOT NULL REFERENCES appointments (id_appointment) ON DELETE RESTRICT,
  type             varchar(20)  NOT NULL CONSTRAINT notifications_type_check CHECK (type IN ('CONFIRMATION', 'REMINDER', 'CANCELLATION')),
  channel          varchar(10)  NOT NULL DEFAULT 'EMAIL' CONSTRAINT notifications_channel_check CHECK (channel IN ('EMAIL')),
  recipient        varchar(255) NOT NULL,
  status           varchar(10)  NOT NULL DEFAULT 'PENDING'
                   CONSTRAINT notifications_status_check CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'CANCELLED')),
  retry_count      smallint     NOT NULL DEFAULT 0 CONSTRAINT notifications_retry_count_check CHECK (retry_count >= 0),
  scheduled_for    timestamptz  NOT NULL,
  sent_at          timestamptz,
  created_at       timestamptz  NOT NULL DEFAULT now()
);

-- ---------- Supporting indexes ----------
CREATE INDEX idx_appointments_dentist_start ON appointments (id_dentist, starts_at);
CREATE INDEX idx_appointments_patient_start ON appointments (id_patient, starts_at);
CREATE INDEX idx_appointments_start_status ON appointments (starts_at, status);
CREATE INDEX idx_appointment_logs_appointment ON appointment_logs (id_appointment);
CREATE INDEX idx_notifications_pending ON notifications (scheduled_for) WHERE status = 'PENDING';

-- ---------- updated_at ----------
-- Done in the database so no client has to remember to set it
CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_set_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_patients_set_updated_at
  BEFORE UPDATE ON patients
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_dentists_set_updated_at
  BEFORE UPDATE ON dentists
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_services_set_updated_at
  BEFORE UPDATE ON services
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_appointments_set_updated_at
  BEFORE UPDATE ON appointments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_medical_records_set_updated_at
  BEFORE UPDATE ON medical_records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------- Row Level Security ----------
-- Enabled with no policies: the public Supabase API can read nothing; the backend connects as table owner.
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE specialties ENABLE ROW LEVEL SECURITY;
ALTER TABLE dentists ENABLE ROW LEVEL SECURITY;
ALTER TABLE services ENABLE ROW LEVEL SECURITY;
ALTER TABLE dentist_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE dentist_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE dentist_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
