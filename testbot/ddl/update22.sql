USE winetestbot;

ALTER TABLE VMs
  MODIFY Status ENUM('dirty', 'reverting', 'sleeping', 'idle', 'running', 'offline', 'maintenance') NOT NULL;
