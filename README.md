# Student Enrollment Database

A SQL Server (T-SQL) database project that models a **Student Course Enrollment System**. This repo contains the full database build script, plus design artifacts (ERD + design document + presentation).

## What’s in this repository

- **`Project 1.sql`**  
  End-to-end T-SQL script that:
  - Creates the database (`StudentCourseEnrollmentSystem`)
  - Creates tables, keys, constraints, computed columns, functions, a stored procedure, seed/sample data, and reporting views

- **`Database Design Document.pdf`**  
  Database design documentation (requirements/design explanations).

- **`_Database Design and Initial ERD.png`**  
  An ERD image showing the schema and relationships.

- **`presentation slide of team 3 (3).pptx`**  
  Slide deck presentation for the project.

## Database capabilities (implemented in `Project 1.sql`)

### Schema / entities
Creates these core tables (with primary keys and relationships):
- `Department`, `Major` (majors belong to departments)
- `Semester`
- `Student` (belongs to a major; includes encrypted password column)
- `Instructor` (belongs to a department; includes encrypted password column)
- `Course` (linked to `Semester`, `Department`, `Instructor`; includes capacity/credits)
- `Enrollment` (joins `Student`  ∞ `Course`, optional `Grade`)
- `Grade`
- `Schedule`, `CourseSchedule` (many-to-many between courses and time slots)
- `CoursePrerequisite` (self-referencing course prerequisites)
- `Waitlist` (waitlist per course with priority)

### Data integrity rules
- Check constraint for `Schedule.DayOfWeek` to valid day names.
- Custom check constraints implemented via scalar functions:
  - Course `Capacity` must be **between 5 and 100**
  - `GradePoint` must be **between 0.00 and 4.00**
- Computed/persisted columns:
  - `Student.FullName` and `Instructor.FullName` using `dbo.fn_FormatFullName`
  - `Course.CourseLevel` derived from credits (`Basic` / `Intermediate` / `Advanced`)

### Security / encryption (demo)
Creates a **master key**, **certificate**, and **symmetric key (AES_128)** and uses them to encrypt example `Password` values for `Student` and `Instructor` rows.

> Note: the script currently includes a hard-coded master key password for demonstration.

### Registration logic (stored procedure)
`sp_RegisterCourse` implements course registration with transaction handling:
- Prevents duplicate enrollment
- Prevents duplicate waitlist entries
- Enrolls if seats are available
- Otherwise adds the student to a waitlist (limit = **15**)
- Returns a human-readable result message via output parameter

### Reporting views
Creates views for common queries:
- `vw_StudentBasicInfo` (student + major + department)
- `vw_DepartmentCourseSummary` (courses per department + concatenated course list)
- `vw_CourseScheduleDetails` (course + semester + instructor + meeting times)
- `vw_CourseRegistrationStatus` (open/full/closed status based on enrollment & semester dates)
- `vw_EnrollmentDetails` (enrollment detail report including grade letter)

## How to run

This script is written for **Microsoft SQL Server / T-SQL**.

1. Open SQL Server Management Studio (SSMS) or Azure Data Studio connected to SQL Server.
2. Run `Project 1.sql` from top to bottom.
3. Query the views, for example:
   - `SELECT * FROM vw_StudentBasicInfo;`
   - `SELECT * FROM vw_CourseRegistrationStatus;`

## Notes / limitations
- This repository appears focused on the **database layer** (schema + logic), and does not include an application/API layer.
- Consider moving secrets (like the master key password) out of source code if this is used beyond a class/demo environment.