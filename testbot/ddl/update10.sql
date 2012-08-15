ALTER TABLE Jobs
  ADD Archived ENUM('Y', 'N') NULL
      AFTER Id,
  ADD INDEX JobsArchived (Archived);

UPDATE Jobs SET Archived = 'N';

ALTER TABLE Jobs
  MODIFY Archived ENUM('Y', 'N') NOT NULL;
