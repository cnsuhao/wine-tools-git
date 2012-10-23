USE winetestbot;

ALTER TABLE VMs
  MODIFY Role ENUM('extra', 'base', 'winetest', 'retired', 'deleted') NOT NULL;
