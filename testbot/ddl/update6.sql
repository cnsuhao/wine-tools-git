ALTER TABLE Steps
  ADD FileType ENUM('exe32', 'exe64', 'patchdlls', 'patchprograms') NULL
      AFTER FileName;

UPDATE Steps
  SET FileType = 'exe64'
  WHERE FileName LIKE '%_test64.exe';

UPDATE Steps
  SET FileType = 'exe32'
  WHERE FileName LIKE '%.exe'
    AND FileType IS NULL;

UPDATE Steps
  SET FileType = 'patchdlls'
  WHERE FileType IS NULL;

ALTER TABLE Steps
  MODIFY FileType ENUM('exe32', 'exe64', 'patchdlls', 'patchprograms') NOT NULL;

CREATE TABLE PendingPatchSets
(
  EMail      VARCHAR(40) NOT NULL,
  TotalParts INT(2)      NOT NULL,
  PRIMARY KEY (EMail, TotalParts)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO PendingPatchSets (EMail, TotalParts)
SELECT EMail, TotalParts
  FROM PendingPatchSeries;

ALTER TABLE PendingPatches
  DROP FOREIGN KEY PendingPatches_ibfk_1;

ALTER TABLE PendingPatches
  DROP PRIMARY KEY;

ALTER TABLE PendingPatches
  CHANGE PendingPatchSeriesEMail PendingPatchSetEMail VARCHAR(40) NOT NULL;

ALTER TABLE PendingPatches
  ADD PendingPatchSetTotalParts INT(2) NULL
      AFTER PendingPatchSetEMail;

UPDATE PendingPatches
   SET PendingPatchSetTotalParts =
       (SELECT TotalParts
          FROM PendingPatchSets
         WHERE EMail = PendingPatchSetEMail);

ALTER TABLE PendingPatches
  MODIFY PendingPatchSetTotalParts INT(2) NOT NULL;

ALTER TABLE PendingPatches
  ADD PRIMARY KEY (PendingPatchSetEMail, PendingPatchSetTotalParts, No);

ALTER TABLE PendingPatches
  ADD FOREIGN KEY (PendingPatchSetEMail, PendingPatchSetTotalParts)
      REFERENCES PendingPatchSets(EMail, TotalParts);

DROP TABLE PendingPatchSeries;

ALTER TABLE Patches
  ADD AffectsTests ENUM('Y', 'N') NULL
      AFTER Disposition;

UPDATE Patches
   SET AffectsTests = 'N';

ALTER TABLE Patches
  MODIFY AffectsTests ENUM('Y', 'N') NOT NULL;
