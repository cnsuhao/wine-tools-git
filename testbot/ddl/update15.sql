USE winetestbot;

ALTER TABLE Steps
  MODIFY FileType ENUM('exe32', 'exe64', 'patchdlls', 'patchprograms') NOT NULL;
