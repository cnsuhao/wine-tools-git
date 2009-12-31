ALTER TABLE VMs
  ADD Type ENUM('base', 'extra', 'build') NULL AFTER BaseOS;

UPDATE VMs
  SET Type = IF(BaseOS = 'Y', 'base', 'extra');

ALTER TABLE VMs
  MODIFY Type ENUM('base', 'extra', 'build') NOT NULL,
  DROP BaseOS;

ALTER TABLE Steps
  ADD Type ENUM('suite', 'single', 'build', 'reconfig') NULL AFTER No;

UPDATE Steps s
  SET s.Type = (SELECT DISTINCT t.Type
                  FROM Tasks t
                 WHERE t.JobId = s.JobId
                   AND t.StepNo = s.No);

ALTER TABLE Steps
  MODIFY Type ENUM('suite', 'single', 'build', 'reconfig') NOT NULL,
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'skipped') NOT NULL;

ALTER TABLE Tasks
  DROP Type,
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'skipped') NOT NULL;
