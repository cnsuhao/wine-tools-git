USE winetestbot;

ALTER TABLE VMs
  MODIFY Status ENUM('dirty', 'reverting', 'sleeping', 'idle', 'running', 'off', 'offline', 'maintenance') NOT NULL;