USE winetestbot;

ALTER TABLE Patches
  MODIFY Id INT(7) NOT NULL AUTO_INCREMENT,
  ADD WebPatchId INT(7) NULL
      AFTER Id,
  ADD INDEX PatchesWebPatchId (WebPatchId);

UPDATE Patches
  SET WebPatchId = Id;
