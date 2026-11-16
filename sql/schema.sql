-- Optional normalized operational schema for an institution's placement office.
-- The public training CSV is student-level classification data. It does not
-- populate Department/Batch, skill records, activities, applications,
-- interviews, offers or employer participation. Use authorized campus data only.

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

CREATE TABLE skills (
    skill_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    skill_name TEXT NOT NULL UNIQUE
);

CREATE TABLE student_skills (
    student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    skill_id BIGINT NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    proficiency TEXT CHECK (proficiency IN ('Beginner','Intermediate','Advanced')),
    PRIMARY KEY (student_id, skill_id)
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

CREATE TABLE student_engagement_events (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'ProfileUpdated','WorkshopAttended','CareerFairAttended',
        'TrainingSession','CounsellingSession','ResumeReviewed',
        'ApplicationSubmitted','Other'
    )),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    details JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE companies (
    company_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name TEXT NOT NULL UNIQUE,
    industry TEXT,
    website TEXT UNIQUE,
    participating BOOLEAN NOT NULL DEFAULT TRUE,
    first_participated_on DATE
);

CREATE TABLE applications (
    application_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    company_id BIGINT NOT NULL REFERENCES companies(company_id),
    role_title TEXT NOT NULL,
    applied_at DATE NOT NULL DEFAULT CURRENT_DATE,
    status TEXT NOT NULL DEFAULT 'Applied'
        CHECK (status IN ('Applied','Shortlisted','Interview','Offered','Rejected','Withdrawn')),
    UNIQUE (student_id, company_id, role_title)
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

CREATE TABLE placement_outcomes (
    student_id BIGINT PRIMARY KEY REFERENCES students(student_id) ON DELETE CASCADE,
    placement_status TEXT NOT NULL CHECK (placement_status IN (
        'Placed','NotPlaced','HigherStudies','NotSeeking'
    )),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Placement rate by department and graduating batch.
CREATE OR REPLACE VIEW placement_rate_by_cohort AS
SELECT d.department_name, b.batch_year,
       COUNT(DISTINCT s.student_id) AS total_students,
       COUNT(DISTINCT CASE WHEN po.placement_status = 'Placed' THEN s.student_id END) AS placed_students,
       ROUND(
         100.0 * COUNT(DISTINCT CASE WHEN po.placement_status = 'Placed' THEN s.student_id END)
         / NULLIF(COUNT(DISTINCT s.student_id), 0), 2
       ) AS placement_rate_pct
FROM students s
LEFT JOIN departments d ON d.department_id = s.department_id
LEFT JOIN batches b ON b.batch_id = s.batch_id
LEFT JOIN placement_outcomes po ON po.student_id = s.student_id
GROUP BY d.department_name, b.batch_year;

-- Recruitment funnel: unique applications, interview rounds and offers.
CREATE OR REPLACE VIEW recruitment_funnel AS
SELECT COUNT(DISTINCT a.application_id) AS applications,
       COUNT(DISTINCT i.interview_id) AS interview_rounds,
       COUNT(DISTINCT o.offer_id) AS offers,
       ROUND(
         100.0 * COUNT(DISTINCT o.offer_id) / NULLIF(COUNT(DISTINCT i.interview_id), 0), 2
       ) AS interview_to_offer_rate_pct
FROM applications a
LEFT JOIN interview_rounds i ON i.application_id = a.application_id
LEFT JOIN offers o ON o.application_id = a.application_id;

-- Employer engagement and campus recruitment participation.
CREATE OR REPLACE VIEW company_participation AS
SELECT c.company_id, c.company_name, c.industry, c.participating,
       COUNT(DISTINCT a.application_id) AS applications,
       COUNT(DISTINCT i.interview_id) AS interview_rounds,
       COUNT(DISTINCT o.offer_id) AS offers
FROM companies c
LEFT JOIN applications a ON a.company_id = c.company_id
LEFT JOIN interview_rounds i ON i.application_id = a.application_id
LEFT JOIN offers o ON o.application_id = a.application_id
GROUP BY c.company_id, c.company_name, c.industry, c.participating;

-- Student engagement by cohort; events are activity counts, not placement outcomes.
CREATE OR REPLACE VIEW student_engagement_by_cohort AS
SELECT d.department_name, b.batch_year,
       COUNT(DISTINCT s.student_id) AS students,
       COUNT(e.event_id) AS engagement_events,
       COUNT(DISTINCT e.student_id) AS engaged_students
FROM students s
LEFT JOIN departments d ON d.department_id = s.department_id
LEFT JOIN batches b ON b.batch_id = s.batch_id
LEFT JOIN student_engagement_events e ON e.student_id = s.student_id
GROUP BY d.department_name, b.batch_year;
