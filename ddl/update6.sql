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
