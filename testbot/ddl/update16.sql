USE winetestbot;

ALTER TABLE VMs
  CHANGE Type OldType ENUM('base', 'extra', 'build', 'retired') NOT NULL,
  ADD Type ENUM('win32', 'win64', 'build') NULL
      AFTER SortOrder,
  ADD Role ENUM('base', 'winetest', 'extra', 'retired') NULL
      AFTER Type;

UPDATE VMs
  SET Type = 'build', Role = 'base'
  WHERE OldType = 'build';

UPDATE VMs
  SET Type = 'win32'
  WHERE Bits = '32' AND OldType <> 'build';

UPDATE VMs
  SET Type = 'win64'
  WHERE Bits = '64' AND OldType <> 'build';

UPDATE VMs
  SET Role = 'base'
  WHERE OldType = 'base';

UPDATE VMs
  SET Role = 'winetest'
  WHERE OldType = 'extra';

UPDATE VMs
  SET Role = 'extra'
  WHERE OldType = 'retired' AND STATUS <> 'offline';

UPDATE VMs
  SET Role = 'retired'
  WHERE OldType = 'retired' AND Status = 'offline';


ALTER TABLE VMs
  DROP OldType,
  DROP Bits,
  MODIFY Type ENUM('win32', 'win64', 'build') NOT NULL,
  MODIFY Role ENUM('extra', 'base', 'winetest', 'retired') NOT NULL;
