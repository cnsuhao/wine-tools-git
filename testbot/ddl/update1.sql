ALTER TABLE Steps
  ADD DebugLevel INT(2) NULL,
  ADD ReportSuccessfulTests ENUM('Y', 'N') NULL;

UPDATE Steps
  SET DebugLevel = 1,
      ReportSuccessfulTests = 'N';

ALTER TABLE Steps
  MODIFY DebugLevel INT(2) NOT NULL,
  MODIFY ReportSuccessfulTests ENUM('Y', 'N') NOT NULL;
