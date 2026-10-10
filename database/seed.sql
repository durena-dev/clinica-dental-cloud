-- Datos ficticios para desarrollo y demostracion. No usar en produccion.
-- Los password_hash son marcadores: la API debe generar los hashes reales.

INSERT INTO roles (name, description) VALUES
  ('ADMIN', 'Administrador del sistema'),
  ('RECEPTIONIST', 'Recepcion y agenda'),
  ('DENTIST', 'Odontologo'),
  ('PATIENT', 'Paciente con acceso al portal');

INSERT INTO specialties (name, description) VALUES
  ('Odontologia general', 'Diagnostico, limpiezas y tratamientos basicos'),
  ('Ortodoncia', 'Correccion de la posicion dental'),
  ('Endodoncia', 'Tratamientos de conducto');

INSERT INTO users (id_role, full_name, email, phone, password_hash) VALUES
  (1, 'Admin Demo',        'admin@demo.test',     '8000-0001', 'HASH_DE_EJEMPLO'),
  (2, 'Recepcion Demo',    'recepcion@demo.test', '8000-0002', 'HASH_DE_EJEMPLO'),
  (3, 'Dra. Ana Mora',     'ana.mora@demo.test',  '8000-0003', 'HASH_DE_EJEMPLO'),
  (3, 'Dr. Luis Rojas',    'luis.rojas@demo.test','8000-0004', 'HASH_DE_EJEMPLO'),
  (4, 'Paciente Uno',      'paciente1@demo.test', '8000-0005', 'HASH_DE_EJEMPLO');

INSERT INTO dentists (id_user, id_specialty, license_number) VALUES
  (3, 1, 'COL-1001'),
  (4, 2, 'COL-1002');

INSERT INTO patients (id_user, full_name, identification, birth_date, phone, email, data_consent_at) VALUES
  (5,    'Paciente Uno',  '1-1111-1111', '1990-05-10', '8000-0005', 'paciente1@demo.test', now()),
  (NULL, 'Paciente Dos',  '2-2222-2222', '1985-11-23', '8000-0006', 'paciente2@demo.test', now());

INSERT INTO services (name, description, duration_minutes, price) VALUES
  ('Consulta de valoracion', 'Primera revision y plan de tratamiento', 30, 15000.00),
  ('Limpieza dental',        'Profilaxis',                              45, 25000.00),
  ('Control de ortodoncia',  'Ajuste de aparatos',                      30, 30000.00);

INSERT INTO dentist_services (id_dentist, id_service) VALUES
  (1, 1), (1, 2),
  (2, 1), (2, 3);

INSERT INTO dentist_schedules (id_dentist, day_of_week, start_time, end_time) VALUES
  (1, 1, '08:00', '12:00'), (1, 1, '13:00', '17:00'),
  (1, 3, '08:00', '12:00'),
  (2, 2, '09:00', '16:00');

INSERT INTO dentist_blocks (id_dentist, starts_at, ends_at, reason) VALUES
  (1, '2026-11-02 08:00-06', '2026-11-02 12:00-06', 'Capacitacion');

INSERT INTO appointments (id_patient, id_dentist, id_service, starts_at, ends_at, status, price_snapshot) VALUES
  (1, 1, 1, '2026-10-12 08:00-06', '2026-10-12 08:30-06', 'CONFIRMED', 15000.00),
  (2, 1, 2, '2026-10-12 09:00-06', '2026-10-12 09:45-06', 'PENDING',   25000.00);

INSERT INTO appointment_logs (id_appointment, changed_by, previous_status, new_status, remarks) VALUES
  (1, 2, NULL,      'PENDING',   'Cita creada por recepcion'),
  (1, 2, 'PENDING', 'CONFIRMED', 'Confirmada por telefono'),
  (2, 2, NULL,      'PENDING',   'Cita creada por recepcion');

INSERT INTO notifications (id_appointment, type, recipient, scheduled_for) VALUES
  (1, 'REMINDER', 'paciente1@demo.test', '2026-10-11 08:00-06');
