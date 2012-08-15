ALTER TABLE Steps
  MODIFY FileType ENUM('exe32', 'exe64', 'patchdlls', 'patchprograms', 'dll32', 'dll64', 'zip') NOT NULL;

CREATE TABLE Branches
(
  Name      VARCHAR(20)     NOT NULL,
  IsDefault ENUM('Y', 'N')  NOT NULL,
  PRIMARY KEY(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO Branches (Name, IsDefault) VALUES ('master', 'Y');

ALTER TABLE Jobs
  ADD BranchName VARCHAR(20) NULL
      AFTER Id;

UPDATE Jobs SET BranchName = 'master';

ALTER TABLE Jobs
  MODIFY BranchName VARCHAR(20) NOT NULL,
  ADD FOREIGN KEY (BranchName) REFERENCES Branches(Name);
