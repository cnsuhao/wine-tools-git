USE winetestbot;

CREATE TABLE Patches
(
  Id          INT(7)       NOT NULL AUTO_INCREMENT,
  Received    DATETIME     NOT NULL,
  Disposition VARCHAR(40)  NOT NULL,
  FromName    VARCHAR(40)  NULL,
  FromEMail   VARCHAR(40)  NULL,
  Subject     VARCHAR(120) NULL,
  PRIMARY KEY (Id)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE PendingPatchSeries
(
  EMail      VARCHAR(40) NOT NULL,
  TotalParts INT(2)      NOT NULL,
  PRIMARY KEY (EMail)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE PendingPatches
(
  PendingPatchSeriesEMail VARCHAR(40) NOT NULL,
  No                      INT(2)      NOT NULL,
  PatchId                 INT(7)      NOT NULL,
  FOREIGN KEY (PendingPatchSeriesEMail) REFERENCES PendingPatchSeries(EMail),
  FOREIGN KEY (PatchId) REFERENCES Patches(Id),
  PRIMARY KEY (PendingPatchSeriesEMail, No)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE Jobs
  ADD PatchId INT(7) NULL,
  ADD FOREIGN KEY (PatchId) REFERENCES Patches(Id);
