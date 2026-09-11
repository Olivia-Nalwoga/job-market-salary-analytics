
CREATE TABLE JobSeeker (
    JobSeekerID     NUMBER          NOT NULL,
    FullName        VARCHAR2(200)   NOT NULL,
    Email           VARCHAR2(200),
    Degree          VARCHAR2(100),
    FieldOfStudy    VARCHAR2(100),
    DegreeLevel     VARCHAR2(50),
    YearsExperience NUMBER(3),
    Location        VARCHAR2(200),
    LastAppliedDate DATE,
    CONSTRAINT JobSeekerPK         PRIMARY KEY (JobSeekerID),
    CONSTRAINT JobSeekerEmailAK    UNIQUE (Email),
    CONSTRAINT YearsExpNonNeg      CHECK (YearsExperience IS NULL OSR YearsExperience >= 0)
);

CREATE TABLE Employer (
    EmployerID      NUMBER          NOT NULL,
    Name            VARCHAR2(200)   NOT NULL,
    Industry        VARCHAR2(100),
    Location        VARCHAR2(200),
    ContactInfo     VARCHAR2(300),
    CompanySize     VARCHAR2(50),
    FoundedYear     NUMBER(4),
    CONSTRAINT EmployerPK          PRIMARY KEY (EmployerID),
    CONSTRAINT EmployerAK1         UNIQUE (Name)
);

CREATE TABLE Skill (
    SkillID         NUMBER          NOT NULL,
    SkillName       VARCHAR2(150)   NOT NULL,
    Category        VARCHAR2(50),
    CONSTRAINT SkillPK             PRIMARY KEY (SkillID),
    CONSTRAINT SkillAK1            UNIQUE (SkillName),
    CONSTRAINT SkillCategoryValues CHECK (Category IS NULL OR Category IN ('Technical','Soft','Other'))
);


CREATE TABLE JobPosting (
    JobID            NUMBER          NOT NULL,
    EmployerID       NUMBER          NOT NULL,
    Title            VARCHAR2(200)   NOT NULL,
    Description      VARCHAR2(2000),
    MinSalary        NUMBER(12,2),
    MaxSalary        NUMBER(12,2),
    EmploymentType   VARCHAR2(50),
    Location         VARCHAR2(200),
    PostedDate       DATE,
    ApplicationCount NUMBER          DEFAULT 0,
    CONSTRAINT JobPostingPK         PRIMARY KEY (JobID),
    CONSTRAINT JobPostingEmployerFK FOREIGN KEY (EmployerID)
                                    REFERENCES Employer (EmployerID),
    CONSTRAINT SalaryRangeCheck     CHECK (
                                       MinSalary IS NULL 
                                       OR MaxSalary IS NULL
                                       OR MinSalary <= MaxSalary
                                    ),
    CONSTRAINT EmploymentTypeVals   CHECK (EmploymentType IS NULL OR EmploymentType IN ('Full-time','Part-time','Contract','Internship','Temporary'))
);

CREATE TABLE JobSeekerSkill (
    JobSeekerID     NUMBER          NOT NULL,
    SkillID         NUMBER          NOT NULL,
    Proficiency     VARCHAR2(50),
    YearsUsing      NUMBER(3),
    CONSTRAINT JobSeekerSkillPK    PRIMARY KEY (JobSeekerID, SkillID),
    CONSTRAINT JSS_SeekerFK        FOREIGN KEY (JobSeekerID)
                                   REFERENCES JobSeeker (JobSeekerID)
                                   ON DELETE CASCADE,
    CONSTRAINT JSS_SkillFK         FOREIGN KEY (SkillID)
                                   REFERENCES Skill (SkillID),
    CONSTRAINT ProficiencyVals     CHECK (Proficiency IS NULL OR Proficiency IN ('Beginner','Intermediate','Advanced','Expert')),
    CONSTRAINT YearsUsingNonNeg    CHECK (YearsUsing IS NULL OR YearsUsing >= 0)
);

CREATE TABLE JobSkill (
    JobID           NUMBER          NOT NULL,
    SkillID         NUMBER          NOT NULL,
    RequiredLevel   VARCHAR2(50),
    CONSTRAINT JobSkillPK          PRIMARY KEY (JobID, SkillID),
    CONSTRAINT JS_JobFK            FOREIGN KEY (JobID)
                                   REFERENCES JobPosting (JobID)
                                   ON DELETE CASCADE,
    CONSTRAINT JS_SkillFK          FOREIGN KEY (SkillID)
                                   REFERENCES Skill (SkillID),
    CONSTRAINT RequiredLevelVals   CHECK (RequiredLevel IS NULL OR RequiredLevel IN ('Preferred','Required','Nice-to-have'))
);

CREATE TABLE Application (
    ApplicationID   NUMBER          NOT NULL,
    JobSeekerID     NUMBER          NOT NULL,
    JobID           NUMBER          NOT NULL,
    ApplicationDate DATE,
    Outcome         VARCHAR2(20),
    InterviewDate   DATE,
    Status          VARCHAR2(20),
    CONSTRAINT ApplicationPK        PRIMARY KEY (ApplicationID),
    CONSTRAINT ApplicationAK1       UNIQUE (JobSeekerID, JobID),
    CONSTRAINT OutcomeValues        CHECK (Outcome IS NULL OR Outcome IN ('Hired','Rejected','Interview')),
    CONSTRAINT StatusValues         CHECK (Status IS NULL OR Status IN ('Applied','Screening','Interview','Offer','Hired','Rejected')),
    CONSTRAINT ApplicationSeekerFK  FOREIGN KEY (JobSeekerID)
                                   REFERENCES JobSeeker (JobSeekerID),
    CONSTRAINT ApplicationJobFK     FOREIGN KEY (JobID)
                                   REFERENCES JobPosting (JobID)
);

CREATE TABLE Salary (
    SalaryID        INT             NOT NULL,
    ApplicationID   INT             NOT NULL,
    Amount          NUMBER(10,2)    NOT NULL,
    Currency        CHAR(3)         DEFAULT 'USD',
    PayFrequency    VARCHAR2(20)    DEFAULT 'Annual',
    JobLevel        VARCHAR2(30),
    SalaryType      VARCHAR2(20)    NOT NULL,
    CONSTRAINT SalaryPK             PRIMARY KEY (SalaryID),
    CONSTRAINT SalaryAK1            UNIQUE (ApplicationID),
    CONSTRAINT SalaryTypeValues     CHECK (SalaryType IN ('Offered', 'Accepted')),
    CONSTRAINT SalaryAmountCheck    CHECK (Amount > 0),
    CONSTRAINT SalaryApplicationFK  FOREIGN KEY (ApplicationID)
                                    REFERENCES Application (ApplicationID)
);


-- TRIGGERS
-- 1) ApplicationCount: maintains JobPosting.ApplicationCount on insert/delete/update of Application.JobID
CREATE OR REPLACE TRIGGER trg_application_count
AFTER INSERT OR DELETE OR UPDATE OF JobID ON Application
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    UPDATE JobPosting
       SET ApplicationCount = NVL(ApplicationCount, 0) + 1
     WHERE JobID = :NEW.JobID;

  ELSIF DELETING THEN
    UPDATE JobPosting
       SET ApplicationCount = GREATEST(NVL(ApplicationCount, 0) - 1, 0)
     WHERE JobID = :OLD.JobID;

  ELSIF UPDATING('JobID') THEN
    IF :OLD.JobID <> :NEW.JobID THEN
      UPDATE JobPosting
         SET ApplicationCount = GREATEST(NVL(ApplicationCount, 0) - 1, 0)
       WHERE JobID = :OLD.JobID;

      UPDATE JobPosting
         SET ApplicationCount = NVL(ApplicationCount, 0) + 1
       WHERE JobID = :NEW.JobID;
    END IF;
  END IF;
END;
/
SHOW ERRORS TRIGGER trg_application_count
/

-- 2) LastAppliedDate: updates JobSeeker.LastAppliedDate on application insert
CREATE OR REPLACE TRIGGER trg_application_last_applied
AFTER INSERT ON Application
FOR EACH ROW
BEGIN
  UPDATE JobSeeker
     SET LastAppliedDate = GREATEST(
                               NVL(LastAppliedDate, DATE '1900-01-01'),
                               NVL(:NEW.ApplicationDate, SYSDATE)
                             )
   WHERE JobSeekerID = :NEW.JobSeekerID;
END;
/
SHOW ERRORS TRIGGER trg_application_last_applied
/

-- 3) Date Validation: prevent future ApplicationDate values

CREATE OR REPLACE TRIGGER trg_application_date_validate
BEFORE INSERT OR UPDATE OF ApplicationDate ON Application
FOR EACH ROW
BEGIN
  IF :NEW.ApplicationDate IS NOT NULL AND :NEW.ApplicationDate > SYSDATE THEN
    RAISE_APPLICATION_ERROR(-20001, 'ApplicationDate cannot be in the future.');
  END IF;
END;


/
SHOW ERRORS TRIGGER trg_application_date_validate



--Queries
--Skills that lead to higher salary offers
--Skills → average offered salary (job requirements) 
--A) Based on job‑required skills (JobSkill)
SELECT
s.SkillName,
ROUND(AVG(sa.Amount),0)               AS avg_offered_salary,sa.salarytype,
COUNT(DISTINCT a.ApplicationID)         AS sample_size
FROM JobSkill js
JOIN Skill s           ON s.SkillID       = js.SkillID
JOIN JobPosting jp     ON jp.JobID        = js.JobID
JOIN Application a     ON a.JobID         = jp.JobID
JOIN Salary sa         ON sa.ApplicationID = a.ApplicationID
WHERE (UPPER(sa.SalaryType)) = 'OFFERED'
GROUP BY s.SkillName,sa.salarytype
HAVING COUNT(DISTINCT a.ApplicationID) >= 1
ORDER BY avg_offered_salary DESC, s.SkillName;

 --Based on applicants’ skills (JobSeekerSkill)
-- Applicant skills → average offered salary (candidate profile) 
SELECT
  s.SkillName,
  ROUND(AVG(sa.Amount), 0) AS avg_offered_salary,
  COUNT(*)                 AS sample_size
FROM JobSeekerSkill jss
JOIN Skill s           ON s.SkillID = jss.SkillID
JOIN Application a     ON a.JobSeekerID = jss.JobSeekerID
JOIN Salary sa         ON sa.ApplicationID = a.ApplicationID
WHERE TRIM(UPPER(sa.SalaryType)) = 'OFFERED'
GROUP BY s.SkillName
ORDER BY avg_offered_salary DESC, s.SkillName;

-- How does salary vary by degree level?
--Offered salary by applicant degree level */
SELECT js.DegreeLevel,
ROUND(AVG(sa.Amount),0) AS avg_offered_salary
FROM Salary sa
JOIN Application a ON a.ApplicationID = sa.ApplicationID
JOIN JobSeeker js ON js.JobSeekerID = a.JobSeekerID
WHERE UPPER(sa.SalaryType) = 'OFFERED'
GROUP BY js.DegreeLevel
ORDER BY avg_offered_salary DESC;

--3) How does salary vary by industry?

/* Offered salary by employer industry */
SELECT
  e.Industry,
  ROUND(AVG(sa.Amount), 0) AS avg_offered_salary,
  COUNT(*)                 AS applications
FROM Salary sa
JOIN Application a ON a.ApplicationID = sa.ApplicationID
JOIN JobPosting jp ON jp.JobID        = a.JobID
JOIN Employer e    ON e.EmployerID    = jp.EmployerID
WHERE TRIM(UPPER(sa.SalaryType)) = 'OFFERED'
GROUP BY e.Industry
ORDER BY avg_offered_salary DESC;


--4) Which industries attract the most job applications?
--Applications volume by industry 

SELECT e.Industry,
COUNT(*) AS applications
FROM Application a
JOIN JobPosting jp ON jp.JobID     = a.JobID
JOIN Employer e    ON e.EmployerID = jp.EmployerID
GROUP BY e.Industry
ORDER BY applications DESC;

--View: Job requirements (skills) per posting

CREATE OR REPLACE VIEW job_requirements AS
SELECT
  jp.JobID,
  jp.Title               AS job_title,
  e.Name                 AS employer_name,
  e.Industry             AS employer_industry,
  s.SkillID,
  s.SkillName,
  s.Category             AS skill_category,
  js.RequiredLevel
FROM JobPosting jp
JOIN Employer   e  ON e.EmployerID = jp.EmployerID
JOIN JobSkill   js ON js.JobID     = jp.JobID
JOIN Skill      s  ON s.SkillID    = js.SkillID;


select * from  job_requirements;

--View: Job applications with salary outcomes
CREATE OR REPLACE VIEW applications_with_salary AS
SELECT a.ApplicationID, a.JobSeekerID ,a.JobID,a.ApplicationDate,a.Status,a.Outcome,a.InterviewDate,
sa.SalaryID,sa.Amount,sa.Currency,sa.PayFrequency,sa.JobLevel,sa.SalaryType        
FROM Application a
JOIN JobPosting jp ON jp.JobID = a.JobID
JOIN Employer   e  ON e.EmployerID = jp.EmployerID
LEFT JOIN Salary sa ON sa.ApplicationID = a.ApplicationID;


select * from  applications_with_salary;




