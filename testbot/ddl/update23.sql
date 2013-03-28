USE winetestbot;

ALTER TABLE Jobs
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'canceled') NOT NULL;

ALTER TABLE Steps
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'canceled', 'skipped') NOT NULL;

ALTER TABLE Tasks
  MODIFY Status ENUM('queued', 'running', 'completed', 'failed', 'canceled', 'skipped') NOT NULL;
