CREATE DATABASE winetestbot DEFAULT CHARSET=utf8 DEFAULT COLLATE=utf8_bin;

USE winetestbot;

CREATE TABLE Users
(
  Name      VARCHAR(40)     NOT NULL,
  EMail     VARCHAR(40)     NOT NULL,
  Password  CHAR(49)        NOT NULL,
  Active    ENUM('Y', 'N')  NOT NULL,
  RealName  VARCHAR(40)     NULL,
  ResetCode CHAR(32)        NULL,
  PRIMARY KEY(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Roles
(
  Name VARCHAR(20) NOT NULL,
  PRIMARY KEY(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE UserRoles
(
  UserName VARCHAR(40) NOT NULL,
  RoleName VARCHAR(20) NOT NULL,
  PRIMARY KEY (UserName, RoleName),
  FOREIGN KEY (UserName) REFERENCES Users(Name),
  FOREIGN KEY (RoleName) REFERENCES Roles(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Sessions
(
  Id        CHAR(32)        NOT NULL,
  UserName  VARCHAR(40)     NOT NULL,
  Permanent ENUM('Y', 'N')  NOT NULL,
  PRIMARY KEY (Id),
  FOREIGN KEY (UserName) REFERENCES Users(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE VMs
(
  Name         VARCHAR(20)      NOT NULL,
  BaseOS       ENUM('Y', 'N')   NOT NULL,
  SortOrder    INT(3)           NOT NULL,
  Bits         ENUM('32', '64') NOT NULL,
  MemSize      INT(5)           UNSIGNED NOT NULL,
  Status       ENUM('reverting', 'sleeping', 'idle', 'running', 'dirty', 'offline') NOT NULL,
  VmxFilePath  VARCHAR(64)      NOT NULL,
  IdleSnapshot VARCHAR(32)      NOT NULL,
  Interactive  ENUM('Y', 'N')   NOT NULL,
  Description  VARCHAR(40)      NULL,
  PRIMARY KEY (Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Jobs
(
  Id        INT(5)      NOT NULL AUTO_INCREMENT,
  UserName  VARCHAR(40) NOT NULL,
  Priority  INT(1)      NOT NULL,
  Status    ENUM('queued', 'running', 'completed', 'failed') NOT NULL,
  Remarks   VARCHAR(50) NULL,
  Submitted DATETIME    NULL,
  Ended     DATETIME    NULL,
  FOREIGN KEY (UserName) REFERENCES Users(Name),
  PRIMARY KEY (Id)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Steps
(
  JobId     INT(5) NOT NULL,
  No        INT(2) NOT NULL,
  Status    ENUM('queued', 'running', 'completed', 'failed') NOT NULL,
  FileName  VARCHAR(64) NOT NULL,
  InStaging ENUM('Y', 'N') NOT NULL,
  PRIMARY KEY (JobId, No),
  FOREIGN KEY (JobId) REFERENCES Jobs(Id)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Tasks
(
  JobId        INT(5) NOT NULL,
  StepNo       INT(2) NOT NULL,
  No           INT(2) NOT NULL,
  Status       ENUM('queued', 'running', 'completed', 'failed') NOT NULL,
  VMName       VARCHAR(20) NOT NULL,
  Type         ENUM('suite', 'single') NOT NULL,
  Timeout      INT(4) NOT NULL,
  CmdLineArg   VARCHAR(256) NULL,
  ChildPid     INT(5) NULL,
  Started      DATETIME NULL,
  Ended        DATETIME NULL,
  TestFailures INT(6) NULL,
  PRIMARY KEY (JobId, StepNo, No),
  FOREIGN KEY(VMName) REFERENCES VMs(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO Roles (Name) Values('admin');
INSERT INTO Roles (Name) Values('wine-devel');
