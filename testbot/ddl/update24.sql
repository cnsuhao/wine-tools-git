USE winetestbot;

ALTER TABLE Jobs
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'boterror', 'canceled') NOT NULL;

ALTER TABLE Steps
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'boterror', 'canceled', 'skipped') NOT NULL;

ALTER TABLE Tasks
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'boterror', 'canceled', 'skipped') NOT NULL;

UPDATE Jobs
  SET Status = 'boterror'
  WHERE Status = 'failed';

UPDATE Steps
  SET Status = 'boterror'
  WHERE Status = 'failed';

UPDATE Tasks
  SET Status = 'boterror'
  WHERE Status = 'failed';

ALTER TABLE Jobs
  MODIFY Status ENUM('queued', 'running', 'completed', 'badpatch', 'badbuild', 'boterror', 'canceled') NOT NULL;

ALTER TABLE Steps
  MODIFY Status ENUM('queued', 'running', 'completed', 'badpatch', 'badbuild', 'boterror', 'canceled', 'skipped') NOT NULL;

ALTER TABLE Tasks
  MODIFY Status ENUM('queued', 'running', 'completed', 'badpatch', 'badbuild', 'boterror', 'canceled', 'skipped') NOT NULL;
