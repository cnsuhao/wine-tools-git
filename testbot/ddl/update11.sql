ALTER TABLE VMs
  MODIFY Type ENUM('base', 'extra', 'build', 'retired') NOT NULL;
