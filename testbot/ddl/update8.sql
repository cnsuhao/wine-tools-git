USE winetestbot;

ALTER TABLE Roles
  ADD IsDefaultRole ENUM('Y', 'N') NULL
      AFTER Name;

UPDATE Roles
  SET IsDefaultRole = 'Y'
  WHERE Name = 'wine-devel';

UPDATE Roles
  SET IsDefaultRole = 'N'
  WHERE Name <> 'wine-devel';

ALTER TABLE Roles
  MODIFY IsDefaultRole ENUM('Y', 'N') NOT NULL;
