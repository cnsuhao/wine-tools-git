USE winetestbot;

ALTER TABLE Users
  ADD Status ENUM('active', 'disabled', 'deleted') NULL
      AFTER Active;

UPDATE Users
  SET Status = 'active'
  WHERE Active = 'Y';

UPDATE Users
  SET Status = 'disabled'
  WHERE Active = 'N';

ALTER TABLE Users
  MODIFY Status ENUM('active', 'disabled', 'deleted') NOT NULL,
  DROP Active;
