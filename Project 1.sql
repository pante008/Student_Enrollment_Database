DROP DATABASE IF EXISTS StudentCourseEnrollmentSystem;
GO

CREATE DATABASE StudentCourseEnrollmentSystem;
GO

USE StudentCourseEnrollmentSystem;
GO

-- Create a master key and certificate for encryption
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Test_P@sswOrd!123';
GO

CREATE CERTIFICATE TestCertificate
WITH SUBJECT = 'Encryption Certificate for Password Column',
     EXPIRY_DATE = '2026-10-31';
GO

CREATE SYMMETRIC KEY TestSymmetricKey
WITH ALGORITHM = AES_128
ENCRYPTION BY CERTIFICATE TestCertificate;
GO

-- Create tables for the Student Course Enrollment System
CREATE TABLE Department
(
    DepartmentID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DepartmentName VARCHAR(100) NOT NULL
);
GO

CREATE TABLE Major
(
    MajorID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DepartmentID INT NOT NULL,
    MajorName VARCHAR(100) NOT NULL,
    FOREIGN KEY (DepartmentID) REFERENCES Department(DepartmentID)
);
GO

CREATE TABLE Semester
(
    SemesterID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    SemesterName VARCHAR(50) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL
);
GO

CREATE TABLE Student
(
    StudentID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    MajorID INT NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(50) NOT NULL,
    Password VARBINARY(256) NOT NULL,
    FOREIGN KEY (MajorID) REFERENCES Major(MajorID)
);
GO

CREATE TABLE Instructor
(
    InstructorID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DepartmentID INT NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(100) NOT NULL,
    Password VARBINARY(256) NOT NULL,
    FOREIGN KEY (DepartmentID) REFERENCES Department(DepartmentID)
);
GO

CREATE TABLE Course
(
    CourseID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    SemesterID INT NOT NULL,
    DepartmentID INT NOT NULL,
    InstructorID INT NOT NULL,
    CourseName VARCHAR(100) NOT NULL,
    Credits INT NOT NULL,
    Capacity INT NOT NULL,
    FOREIGN KEY (SemesterID)   REFERENCES Semester(SemesterID),
    FOREIGN KEY (DepartmentID) REFERENCES Department(DepartmentID),
    FOREIGN KEY (InstructorID)   REFERENCES Instructor(InstructorID)
);
GO

CREATE TABLE Grade
(
    GradeID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    GradeLetter CHAR(2) NOT NULL,
    GradePoint DECIMAL(3,2) NOT NULL
);
GO

CREATE TABLE Enrollment
(
    EnrollmentID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StudentID INT NOT NULL,
    CourseID INT NOT NULL,
    GradeID INT NULL,
    EnrollmentDate DATE NOT NULL DEFAULT GETDATE(),
    FOREIGN KEY (StudentID) REFERENCES Student(StudentID),
    FOREIGN KEY (CourseID)  REFERENCES Course(CourseID),
    FOREIGN KEY (GradeID)   REFERENCES Grade(GradeID)
);
GO

CREATE TABLE Schedule
(
    ScheduleID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DayOfWeek VARCHAR(10) NOT NULL
        CHECK (DayOfWeek IN ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
    StartTime TIME NOT NULL,
    EndTime TIME NOT NULL
);
GO

CREATE TABLE CourseSchedule
(
    CourseID INT NOT NULL,
    ScheduleID INT NOT NULL,
    PRIMARY KEY (CourseID, ScheduleID),
    FOREIGN KEY (CourseID)   REFERENCES Course(CourseID),
    FOREIGN KEY (ScheduleID) REFERENCES Schedule(ScheduleID)
);
GO

CREATE TABLE CoursePrerequisite
(
    CourseID INT NOT NULL,
    PrerequisiteCourseID INT NOT NULL,
    PRIMARY KEY (CourseID, PrerequisiteCourseID),
    FOREIGN KEY (CourseID)             REFERENCES Course(CourseID),
    FOREIGN KEY (PrerequisiteCourseID) REFERENCES Course(CourseID)
);
GO

CREATE TABLE Waitlist
(
    WaitlistID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StudentID INT NOT NULL,
    CourseID INT NOT NULL,
    RequestDate DATE NOT NULL DEFAULT GETDATE(),
    Priority INT NOT NULL,
    FOREIGN KEY (StudentID) REFERENCES Student(StudentID),
    FOREIGN KEY (CourseID)  REFERENCES Course(CourseID)
);
GO

-- Create check constraints for course capacity, from 5 to 100
CREATE FUNCTION dbo.fn_CheckCapacity(@Capacity INT)
RETURNS BIT
AS
BEGIN
    IF @Capacity BETWEEN 5 AND 100
        RETURN 1;
    RETURN 0;
END;
GO

ALTER TABLE Course
ADD CONSTRAINT CK_Course_Capacity CHECK (dbo.fn_CheckCapacity(Capacity) = 1);
GO

-- Create check constraints for grade point, from 0.00 to 4.00
CREATE FUNCTION dbo.fn_CheckGradePoint(@GradePoint DECIMAL(3,2))
RETURNS BIT
AS
BEGIN
    IF @GradePoint BETWEEN 0 AND 4.0
        RETURN 1;
    RETURN 0;
END;
GO

ALTER TABLE Grade
ADD CONSTRAINT CK_Grade_GradePoint CHECK (dbo.fn_CheckGradePoint(GradePoint) = 1);
GO

-- Create fullname functions for Student and Instructor
CREATE FUNCTION dbo.fn_FormatFullName
(
    @FirstName VARCHAR(50),
    @LastName  VARCHAR(50)
)
RETURNS VARCHAR(101)
WITH SCHEMABINDING
AS
BEGIN
    RETURN (@FirstName + ' ' + @LastName);
END;
GO

ALTER TABLE Student
ADD FullName AS dbo.fn_FormatFullName(FirstName, LastName) PERSISTED;
GO

ALTER TABLE Instructor
ADD FullName AS dbo.fn_FormatFullName(FirstName, LastName) PERSISTED;
GO

-- Create a function to determine course level based on credits
-- 4 credits = Advanced, 3 credits = Intermediate, 2 or less = Basic
CREATE FUNCTION dbo.fn_CourseLevel
(
    @Credits INT
)
RETURNS VARCHAR(50)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Level VARCHAR(50);
    IF @Credits >= 4
        SET @Level = 'Advanced';
    ELSE IF @Credits = 3
        SET @Level = 'Intermediate';
    ELSE 
        SET @Level = 'Basic';
    RETURN @Level;
END;
GO

ALTER TABLE Course
ADD CourseLevel AS dbo.fn_CourseLevel(Credits) PERSISTED;
GO

-- Create procedure for student registration
CREATE PROCEDURE sp_RegisterCourse
    @StudentID INT,
    @CourseID INT,
    @ResultMessage VARCHAR(200) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;
    DECLARE @Capacity INT,
            @EnrolledCount INT,
            @WaitlistCount INT,
            @WaitlistLimit INT = 15;  -- set a limit for the waitlist

    -- check if the student is already enrolled in the course
    IF EXISTS (SELECT 1 FROM Enrollment WHERE StudentID = @StudentID AND CourseID = @CourseID)
    BEGIN
        SET @ResultMessage = 'Already enrolled in the course.';
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- check if the student is already on the waitlist
    IF EXISTS (SELECT 1 FROM Waitlist WHERE StudentID = @StudentID AND CourseID = @CourseID)
    BEGIN
        SET @ResultMessage = 'Already on the waitlist for this course.';
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- check if the course exists
    SELECT @Capacity = Capacity
    FROM Course
    WHERE CourseID = @CourseID;

    IF @Capacity IS NULL
    BEGIN
         SET @ResultMessage = 'Course not found';
         ROLLBACK TRANSACTION;
         RETURN;
    END

    SELECT @EnrolledCount = COUNT(*)
    FROM Enrollment
    WHERE CourseID = @CourseID;

    -- check if the course is full, if not, enroll the student
    IF @EnrolledCount < @Capacity
    BEGIN
         INSERT INTO Enrollment (StudentID, CourseID, EnrollmentDate)
         VALUES (@StudentID, @CourseID, GETDATE());
         SET @ResultMessage = 'Successfully enrolled in the course.';
         COMMIT TRANSACTION;
         RETURN;
    END
    ELSE
    BEGIN
         
         SELECT @WaitlistCount = COUNT(*)
         FROM Waitlist
         WHERE CourseID = @CourseID;
         
         -- check if the waitlist is full, if not, add the student to the waitlist, otherwise, rollback
         IF @WaitlistCount < @WaitlistLimit
         BEGIN
              INSERT INTO Waitlist (StudentID, CourseID, RequestDate, Priority)
              VALUES (@StudentID, @CourseID, GETDATE(), @WaitlistCount + 1);
              SET @ResultMessage = 'Course is full; you have been added to the waitlist.';
              COMMIT TRANSACTION;
              RETURN;
         END
         ELSE
         BEGIN
              SET @ResultMessage = 'Course and waitlist are both full. Registration failed.';
              ROLLBACK TRANSACTION;
              RETURN;
         END
    END
END;
GO

-- Insert sample data into the tables
INSERT INTO Department
    (DepartmentName)
VALUES
    ('Computer Science'),
    ('Mathematics'),
    ('Physics'),
    ('Chemistry'),
    ('Biology'),
    ('History'),
    ('English'),
    ('Economics'),
    ('Philosophy'),
    ('Psychology');
GO

INSERT INTO Major
    (DepartmentID, MajorName)
VALUES
    (1, 'Software Engineering'),
    (1, 'Data Science'),
    (2, 'Applied Mathematics'),
    (3, 'Astrophysics'),
    (4, 'Organic Chemistry'),
    (5, 'Microbiology'),
    (6, 'Ancient History'),
    (7, 'Literature'),
    (8, 'Finance'),
    (9, 'Philosophy');
GO

INSERT INTO Semester
    (SemesterName, StartDate, EndDate)
VALUES
    ('Fall 2022', '2022-09-01', '2022-12-20'),
    ('Spring 2023', '2023-01-15', '2023-05-01'),
    ('Summer 2023', '2023-06-01', '2023-08-01'),
    ('Fall 2023', '2023-09-01', '2023-12-20'),
    ('Spring 2024', '2024-01-15', '2024-05-01'),
    ('Summer 2024', '2024-06-01', '2024-08-01'),
    ('Fall 2024', '2024-09-01', '2024-12-20'),
    ('Spring 2025', '2025-01-15', '2025-05-01'),
    ('Summer 2025', '2025-06-01', '2025-08-01'),
    ('Fall 2025', '2025-09-01', '2025-12-20');
GO


OPEN SYMMETRIC KEY TestSymmetricKey
DECRYPTION BY CERTIFICATE TestCertificate;
GO

INSERT INTO Student
    (MajorID, FirstName, LastName, Email, Password)
VALUES
    (1, 'Alice', 'Smith', 'alice@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'AlicePwd1'))),
    (2, 'Bob', 'Johnson', 'bob@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'BobPwd1'))),
    (3, 'Carol', 'Williams', 'carol@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'CarolPwd1'))),
    (4, 'David', 'Brown', 'david@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'DavidPwd1'))),
    (5, 'Eve', 'Jones', 'eve@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'EvePwd1'))),
    (6, 'Frank', 'Garcia', 'frank@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'FrankPwd1'))),
    (7, 'Grace', 'Miller', 'grace@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'GracePwd1'))),
    (8, 'Hank', 'Davis', 'hank@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'HankPwd1'))),
    (9, 'Ivy', 'Rodriguez', 'ivy@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'IvyPwd1'))),
    (10, 'Jack', 'Martinez', 'jack@example.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'JackPwd1')));
GO

INSERT INTO Instructor (DepartmentID, FirstName, LastName, Email, Password)
VALUES
    (1, 'Alice', 'Wang', 'alice.wang@cs.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'AliceCS1'))),
    (1, 'Bob', 'Chen', 'bob.chen@cs.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'BobCS1'))),
    (1, 'Carol', 'Li', 'carol.li@cs.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'CarolCS1'))),
    (1, 'David', 'Zhang', 'david.zhang@cs.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'DavidCS1'))),
    (2, 'Evan', 'Miller', 'evan.miller@math.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'EvanMath1'))),
    (3, 'Fiona', 'Smith', 'fiona.smith@physics.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'FionaPhys1'))),
    (4, 'George', 'Jones', 'george.jones@chem.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'GeorgeChem1'))),
    (5, 'Hannah', 'Brown', 'hannah.brown@bio.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'HannahBio1'))),
    (6, 'Ian', 'Taylor', 'ian.taylor@history.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'IanHist1'))),
    (7, 'Jane', 'Wilson', 'jane.wilson@eng.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'JaneEng1'))),
    (8, 'Kevin', 'Lee', 'kevin.lee@econ.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'KevinEcon1'))),
    (9, 'Linda', 'Martinez', 'linda.martinez@phil.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'LindaPhil1'))),
    (10,'Mike', 'Davis', 'mike.davis@psych.com', EncryptByKey(Key_GUID(N'TestSymmetricKey'), CONVERT(VARBINARY, 'MikePsych1')));
GO

CLOSE SYMMETRIC KEY TestSymmetricKey;
GO

INSERT INTO Course (SemesterID, DepartmentID, InstructorID, CourseName, Credits, Capacity)
VALUES
  (1, 1, 1,  'Intro to Programming',                  3, 40),
  (2, 1, 2,  'Data Structures',                       4, 35),
  (3, 1, 3,  'Algorithms',                            4, 30),
  (4, 1, 4,  'Computer Organization',                 3, 40),
  (5, 1, 1,  'Operating Systems',                     4, 30),
  (6, 1, 4,  'Databases',                             3, 40),
  (7, 1, 3,  'Networks',                              3, 30),
  (8, 1, 3, 'Software Engineering',                  4, 40),
  (9, 1, 2,  'Artificial Intelligence',               4, 35),
  (10, 1, 4, 'Machine Learning',                      4, 30),
  (1, 1, 1,  'Computer Graphics',                     3, 40),
  (2, 1, 3, 'Web Programming',                       3, 35),
  (3, 1, 1,  'Mobile Application Development',        3, 30),
  (4, 1, 4,  'Cybersecurity Fundamentals',            4, 40),
  (5, 1, 2,  'Cloud Computing',                       4, 30),
  (6, 1, 3, 'Parallel Computing',                    3, 40),
  (7, 1, 1,  'Programming Languages',                 3, 35),
  (8, 1, 4,  'Compiler Construction',                 4, 30),
  (9, 1, 3,  'Distributed Systems',                   4, 40),
  (10, 1, 2,'Big Data Analytics',                    4, 30),
  (3, 2, 5,  'Calculus I',                            3, 40),
  (4, 2, 5,  'Calculus II',                           4, 35),
  (5, 3, 6,  'Physics I',                             3, 30),
  (6, 4, 7,  'Organic Chemistry',                     3, 40),
  (7, 5, 8,  'Molecular Biology',                     3, 35),
  (8, 6, 9,  'World History',                         3, 30),
  (9, 7, 10,  'English Literature',                    3, 40),
  (10, 8, 11, 'Microeconomics',                        3, 35),
  (1, 9, 12,  'Introduction to Philosophy',            2, 30),
  (2, 10, 13, 'Cognitive Psychology',                  3, 40);
GO

INSERT INTO Grade
    (GradeLetter, GradePoint)
VALUES
    ('A', 4.0),
    ('A-', 3.7),
    ('B+', 3.3),
    ('B', 3.0),
    ('B-', 2.7),
    ('C+', 2.3),
    ('C', 2.0),
    ('D', 1.0),
    ('F', 0.0),
    ('P', 0.0);  
GO

INSERT INTO Enrollment
    (StudentID, CourseID, GradeID, EnrollmentDate)
VALUES
    (1, 1, 1, '2024-04-05'),
    (2, 1, 2, '2024-04-06'),
    (3, 2, 3, '2024-04-07'),
    (4, 2, 4, '2024-04-08'),
    (5, 3, 1, '2024-04-09'),
    (6, 3, 2, '2024-04-10'),
    (7, 4, 3, '2024-04-11'),
    (8, 5, 4, '2024-04-12'),
    (9, 6, 1, '2024-04-13'),
    (10, 7, 2, '2024-04-14'),
    (1, 8,  NULL, '2024-12-05'),
    (2, 8,  NULL, '2024-12-06'),
    (3, 8,  NULL, '2024-12-07'),
    (4, 8,  NULL, '2024-12-08'),
    (5, 8,  NULL, '2024-12-09'),
    (6, 8,  NULL, '2024-12-10'),
    (7, 8,  NULL, '2024-12-11'),
    (1, 9,  NULL, '2025-02-10'),
    (2, 9,  NULL, '2025-02-11'),
    (3, 9,  NULL, '2025-02-12'),
    (4, 9,  NULL, '2025-02-13'),
    (5, 9,  NULL, '2025-02-14'),
    (6, 10, NULL, '2025-04-05'),
    (7, 10, NULL, '2025-04-06'),
    (8, 10, NULL, '2025-04-07'),
    (9, 10, NULL, '2025-04-08'),
    (10,10, NULL, '2025-04-09');
GO

INSERT INTO Schedule
    (DayOfWeek, StartTime, EndTime)
VALUES
    ('Monday', '09:00', '12:00'),
    ('Tuesday', '10:00', '13:00'),
    ('Wednesday', '09:00', '10:30'),
    ('Thursday', '10:00', '11:30'),
    ('Friday', '12:00', '15:00'),
    ('Monday', '13:00', '14:30'),
    ('Tuesday', '13:00', '15:00'),
    ('Wednesday', '18:30', '21:30'),
    ('Thursday', '15:00', '16:30'),
    ('Friday', '15:00', '18:00');
GO

INSERT INTO CourseSchedule (CourseID, ScheduleID)
VALUES
    (1, 1),
    (2, 2),
    (3, 3),
    (4, 4),
    (5, 5),
    (6, 6),
    (7, 7),
    (8, 8),
    (9, 9),
    (10, 10),
    (11, 1),
    (12, 2),
    (13, 3),
    (14, 4),
    (15, 5),
    (16, 6),
    (17, 7),
    (18, 8),
    (19, 9),
    (20, 10),
    (21, 1),
    (22, 2),
    (23, 3),
    (24, 4),
    (25, 5),
    (26, 6),
    (27, 7),
    (28, 8),
    (29, 9);

INSERT INTO CoursePrerequisite
    (CourseID, PrerequisiteCourseID)
VALUES
    (2, 1),
    (3, 1),
    (4, 2),
    (5, 3),
    (6, 3),
    (7, 5),
    (8, 5),
    (9, 7),
    (10, 8),
    (10, 9);
GO

INSERT INTO Waitlist
    (StudentID, CourseID, RequestDate, Priority)
VALUES
    (1, 2, '2024-09-10', 1),
    (2, 2, '2024-09-10', 2),
    (3, 2, '2024-09-11', 3),
    (4, 3, '2024-09-12', 1),
    (5, 4, '2024-09-13', 1),
    (6, 5, '2024-09-14', 1),
    (7, 6, '2024-09-15', 1),
    (8, 7, '2024-09-16', 1),
    (9, 8, '2024-09-17', 1),
    (10, 9, '2024-09-18', 1);
GO

-- Create views for the Student Information
CREATE VIEW vw_StudentBasicInfo
AS
SELECT 
    s.StudentID,
    s.FullName,
    s.Email,
    m.MajorName,
    d.DepartmentName
FROM Student s
JOIN Major m ON s.MajorID = m.MajorID
JOIN Department d ON m.DepartmentID = d.DepartmentID;
GO

-- Create views for the Each Department's Courses
CREATE VIEW vw_DepartmentCourseSummary
AS
SELECT
    d.DepartmentID,
    d.DepartmentName,
    COUNT(c.CourseID) AS CourseCount,
    STUFF(
        (SELECT ', ' + c2.CourseName
         FROM Course c2
         WHERE c2.DepartmentID = d.DepartmentID
         FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, ''
    ) AS CourseList
FROM Department d
LEFT JOIN Course c ON d.DepartmentID = c.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName;
GO

-- Create views for the Course Schedule details
CREATE VIEW vw_CourseScheduleDetails
AS
    SELECT
        c.CourseID,
        c.CourseName,
        sem.SemesterName,
        i.FullName AS InstructorName,
        s.DayOfWeek,
        CONVERT(VARCHAR(5), s.StartTime, 108) AS StartTime,
        CONVERT(VARCHAR(5), s.EndTime, 108) AS EndTime
    FROM Course c
        JOIN Semester sem ON c.SemesterID = sem.SemesterID
        JOIN Instructor i ON c.InstructorID = i.InstructorID
        JOIN CourseSchedule cs ON c.CourseID = cs.CourseID
        JOIN Schedule s ON cs.ScheduleID = s.ScheduleID;
GO

-- Create views for the Course Registration status
CREATE VIEW vw_CourseRegistrationStatus
AS
SELECT
    c.CourseID,
    c.CourseName,
    sem.SemesterName,
    c.Capacity,
    ISNULL(e.EnrolledCount, 0) AS EnrolledCount,
    (c.Capacity - ISNULL(e.EnrolledCount, 0)) AS RemainingSeats,
    CASE 
        WHEN sem.EndDate < GETDATE() THEN 'Closed'
        WHEN ISNULL(e.EnrolledCount, 0) >= c.Capacity THEN 'Full'
        WHEN ISNULL(e.EnrolledCount, 0) = 0 THEN 'Open'
        ELSE 'Open'
    END AS RegistrationStatus
FROM Course c
JOIN Semester sem ON c.SemesterID = sem.SemesterID
LEFT JOIN (
    SELECT CourseID, COUNT(*) AS EnrolledCount
    FROM Enrollment
    GROUP BY CourseID
) e ON c.CourseID = e.CourseID;
GO

-- Create views for the Student Enrollment details
CREATE VIEW vw_EnrollmentDetails
AS
    SELECT
        e.EnrollmentID,
        s.StudentID,
        s.FullName AS StudentName,
        c.CourseName,
        sem.SemesterName,
        i.FullName AS InstructorName,
        e.EnrollmentDate,
        g.GradeLetter
    FROM Enrollment e
        JOIN Student s ON e.StudentID = s.StudentID
        JOIN Course c ON e.CourseID = c.CourseID
        JOIN Semester sem ON c.SemesterID = sem.SemesterID
        JOIN Instructor i ON c.InstructorID = i.InstructorID
        LEFT JOIN Grade g ON e.GradeID = g.GradeID;
GO