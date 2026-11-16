-- Optional normalized operational schema for an institution's placement office.
-- This schema is an extension model; the public training CSV does not populate
-- department/batch, applications, interview rounds or offers.

CREATE TABLE departments (
    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_name TEXT NOT NULL UNIQUE
);

CREATE TABLE batches (
    batch_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_year INTEGER NOT NULL UNIQUE CHECK (batch_year BETWEEN 2000 AND 2100)
);

CREATE TABLE students (
    student_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    institution_student_ref TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    email TEXT UNIQUE,
    department_id BIGINT REFERENCES departments(department_id),
    batch_id BIGINT REFERENCES batches(batch_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE academic_profiles (
    student_id BIGINT PRIMARY KEY REFERENCES students(student_id) ON DELETE CASCADE,
    cgpa NUMERIC(4,2) CHECK (cgpa BETWEEN 0 AND 10),
    ssc_marks NUMERIC(5,2) CHECK (ssc_marks BETWEEN 0 AND 100),
    hsc_marks NUMERIC(5,2) CHECK (hsc_marks BETWEEN 0 AND 100),
    aptitude_score NUMERIC(5,2),
    soft_skills_rating NUMERIC(3,2),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE internships (
    internship_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    organisation_name TEXT NOT NULL,
    start_date DATE,
    end_date DATE,
    description TEXT,
    CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

CREATE TABLE applications (
    application_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    employer_name TEXT NOT NULL,
    role_title TEXT NOT NULL,
    applied_at DATE NOT NULL DEFAULT CURRENT_DATE,
    status TEXT NOT NULL DEFAULT 'Applied'
        CHECK (status IN ('Applied','Shortlisted','Interview','Offered','Rejected','Withdrawn')),
    UNIQUE (student_id, employer_name, role_title)
);

CREATE TABLE interview_rounds (
    interview_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL REFERENCES applications(application_id) ON DELETE CASCADE,
    round_number INTEGER NOT NULL CHECK (round_number > 0),
    interview_date TIMESTAMPTZ,
    outcome TEXT CHECK (outcome IN ('Pending','Passed','Failed','NoShow')),
    feedback TEXT,
    UNIQUE (application_id, round_number)
);

CREATE TABLE offers (
    offer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id BIGINT NOT NULL UNIQUE REFERENCES applications(application_id) ON DELETE CASCADE,
    offered_at DATE NOT NULL DEFAULT CURRENT_DATE,
    annual_ctc NUMERIC(12,2) CHECK (annual_ctc >= 0),
    offer_status TEXT NOT NULL DEFAULT 'Pending'
        CHECK (offer_status IN ('Pending','Accepted','Declined','Expired'))
);

-- Placement rate by department and graduating batch.
CREATE VIEW placement_rate_by_cohort AS
SELECT d.department_name, b.batch_year,
       COUNT(DISTINCT s.student_id) AS total_students,
       COUNT(DISTINCT CASE WHEN o.offer_status = 'Accepted' THEN s.student_id END) AS placed_students,
       ROUND(
         100.0 * COUNT(DISTINCT CASE WHEN o.offer_status = 'Accepted' THEN s.student_id END)
         / NULLIF(COUNT(DISTINCT s.student_id), 0), 2
       ) AS placement_rate_pct
FROM students s
LEFT JOIN departments d ON d.department_id = s.department_id
LEFT JOIN batches b ON b.batch_id = s.batch_id
LEFT JOIN applications a ON a.student_id = s.student_id
LEFT JOIN offers o ON o.application_id = a.application_id
GROUP BY d.department_name, b.batch_year;

-- Funnel counts support application -> interview -> offer analysis.
CREATE VIEW recruitment_funnel AS
SELECT COUNT(DISTINCT a.application_id) AS applications,
       COUNT(DISTINCT i.interview_id) AS interview_rounds,
       COUNT(DISTINCT o.offer_id) AS offers
FROM applications a
LEFT JOIN interview_rounds i ON i.application_id = a.application_id
LEFT JOIN offers o ON o.application_id = a.application_id;
